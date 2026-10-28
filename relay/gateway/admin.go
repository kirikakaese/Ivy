// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/subtle"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

//go:embed admin
var adminFiles embed.FS

type adminStatus struct {
	Status     string            `json:"status"`
	Problems   []string          `json:"problems"`
	Notes      []string          `json:"notes"`
	Checked    time.Time         `json:"checked"`
	BundleID   string            `json:"bundleId"`
	Relay      relayStatus       `json:"relay"`
	Pushes     statsSnapshot     `json:"pushes"`
	Components []componentStatus `json:"components"`
}

// buildStatus sums up the relay's health for the admin page.
func buildStatus(relay relayStatus, pushes statsSnapshot, bundleID string, now time.Time) adminStatus {
	status := adminStatus{Status: "ok", Problems: []string{}, Notes: []string{}, Checked: now, BundleID: bundleID, Relay: relay, Pushes: pushes}
	if !relay.Reachable {
		status.Status = "down"
		status.Problems = append(status.Problems, "MollySocket doesn't answer, so no wake-ups are sent.")
	}
	latestFailed := pushes.LastFailure != nil && (pushes.LastSuccess == nil || pushes.LastFailure.After(*pushes.LastSuccess))
	if latestFailed && now.Sub(*pushes.LastFailure) < time.Hour {
		if status.Status == "ok" {
			status.Status = "degraded"
		}
		status.Problems = append(status.Problems, "Apple rejected the latest wake-up: "+pushes.LastError)
	} else if latestFailed {
		// On a quiet relay, an old rejection doesn't make it look broken.
		status.Notes = append(status.Notes, "Apple rejected the latest wake-up, more than an hour ago: "+pushes.LastError)
	} else if pushes.Failed24h > 0 {
		status.Notes = append(status.Notes, plural(pushes.Failed24h, "wake-up", "wake-ups")+" failed in the last 24 hours; later ones went through.")
	}
	if relay.Reachable && relay.Forbidden > 0 {
		status.Notes = append(status.Notes, plural(int(relay.Forbidden), "Ivy Push device was", "Ivy Push devices were")+" removed from an account. Ivy adds a new one the next time it registers.")
	}
	if relay.Reachable && relay.Connections == 0 {
		status.Notes = append(status.Notes, "No accounts are connected yet.")
	}
	return status
}

func plural(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

type admin struct {
	password string
	monitor  *monitor
	posts    *posts
	now      func() time.Time
	sleep    func(time.Duration)

	mu       sync.Mutex
	failures map[string][]time.Time
}

const (
	loginAttempts = 10
	loginWindow   = 15 * time.Minute
)

// clientIP is the visitor's address as Caddy passes it on.
func clientIP(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		return strings.TrimSpace(strings.Split(forwarded, ",")[0])
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

// recentFailures drops failed logins older than the window and returns how
// many are left for the address.
func (a *admin) recentFailures(ip string, add bool) int {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.failures == nil {
		a.failures = map[string][]time.Time{}
	}
	cutoff := a.now().Add(-loginWindow)
	for key, times := range a.failures {
		kept := times[:0]
		for _, t := range times {
			if t.After(cutoff) {
				kept = append(kept, t)
			}
		}
		if len(kept) == 0 {
			delete(a.failures, key)
		} else {
			a.failures[key] = kept
		}
	}
	if add {
		a.failures[ip] = append(a.failures[ip], a.now())
	}
	return len(a.failures[ip])
}

func (a *admin) authorized(r *http.Request) bool {
	user, password, ok := r.BasicAuth()
	return ok &&
		subtle.ConstantTimeCompare([]byte(user), []byte("admin")) == 1 &&
		subtle.ConstantTimeCompare([]byte(password), []byte(a.password)) == 1
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(value)
}

// sameOrigin rejects changes sent from other sites: browsers send the
// password along with any request to the admin page, so a change must come
// from the admin page itself, as JSON.
func sameOrigin(r *http.Request, needJSON bool) bool {
	if site := r.Header.Get("Sec-Fetch-Site"); site != "" && site != "same-origin" {
		return false
	}
	if origin := r.Header.Get("Origin"); origin != "" {
		if origin != "https://"+r.Host && origin != "http://"+r.Host {
			return false
		}
	}
	return !needJSON || strings.HasPrefix(r.Header.Get("Content-Type"), "application/json")
}

// servePosts handles the posts on the status page:
//
//	GET    /admin/posts                 all posts
//	POST   /admin/posts                 new post (postInput)
//	POST   /admin/posts/<id>/updates    new step ({"step","message"})
//	DELETE /admin/posts/<id>            delete a post
func (a *admin) servePosts(w http.ResponseWriter, r *http.Request) {
	rest := strings.Trim(strings.TrimPrefix(r.URL.Path, "/admin/posts"), "/")
	if r.Method == http.MethodGet && rest == "" {
		writeJSON(w, map[string]any{"posts": a.posts.all(), "components": components, "steps": postSteps})
		return
	}
	if r.Method == http.MethodGet {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	if !sameOrigin(r, r.Method != http.MethodDelete) {
		http.Error(w, "Changes have to come from the admin page.", http.StatusForbidden)
		return
	}
	body := http.MaxBytesReader(w, r.Body, 16<<10)
	var err error
	switch {
	case r.Method == http.MethodPost && rest == "":
		var in postInput
		if err = json.NewDecoder(body).Decode(&in); err == nil {
			var created *post
			if created, err = a.posts.create(in); err == nil {
				w.WriteHeader(http.StatusCreated)
				writeJSON(w, created)
				return
			}
		}
	case r.Method == http.MethodPost && strings.HasSuffix(rest, "/updates"):
		var in struct {
			Step    string `json:"step"`
			Message string `json:"message"`
		}
		if err = json.NewDecoder(body).Decode(&in); err == nil {
			err = a.posts.update(strings.TrimSuffix(rest, "/updates"), in.Step, in.Message)
		}
	case r.Method == http.MethodDelete && rest != "" && !strings.Contains(rest, "/"):
		err = a.posts.remove(rest)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if err != nil {
		http.Error(w, "That didn't work. Check the fields and try again.", http.StatusBadRequest)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// register adds the admin page under /admin/. Without a password, there is
// no admin page.
func (a *admin) register(mux *http.ServeMux) {
	if a.password == "" {
		return
	}
	static, _ := fs.Sub(adminFiles, "admin")
	files := http.StripPrefix("/admin/", http.FileServer(http.FS(static)))
	mux.HandleFunc("/admin", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/admin/", http.StatusMovedPermanently)
	})
	mux.HandleFunc("/admin/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		ip := clientIP(r)
		if a.recentFailures(ip, false) >= loginAttempts {
			w.Header().Set("Retry-After", strconv.Itoa(int(loginWindow.Seconds())))
			http.Error(w, "Too many failed logins. Try again later.", http.StatusTooManyRequests)
			return
		}
		if !a.authorized(r) {
			if _, _, sent := r.BasicAuth(); sent {
				a.recentFailures(ip, true)
			}
			a.sleep(time.Second)
			w.Header().Set("WWW-Authenticate", `Basic realm="Ivy Status admin", charset="UTF-8"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/admin/posts") {
			a.servePosts(w, r)
			if r.Method != http.MethodGet {
				a.monitor.refresh()
			}
			return
		}
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.URL.Path == "/admin/status.json" {
			writeJSON(w, a.monitor.evaluate())
			return
		}
		files.ServeHTTP(w, r)
	})
}
