// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/subtle"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"time"
)

//go:embed admin
var adminFiles embed.FS

type adminStatus struct {
	Status   string        `json:"status"`
	Problems []string      `json:"problems"`
	Notes    []string      `json:"notes"`
	Checked  time.Time     `json:"checked"`
	BundleID string        `json:"bundleId"`
	Relay    relayStatus   `json:"relay"`
	Pushes   statsSnapshot `json:"pushes"`
}

// buildStatus sums up the relay's health for the admin page.
func buildStatus(relay relayStatus, pushes statsSnapshot, bundleID string, now time.Time) adminStatus {
	status := adminStatus{Status: "ok", Problems: []string{}, Notes: []string{}, Checked: now, BundleID: bundleID, Relay: relay, Pushes: pushes}
	if !relay.Reachable {
		status.Status = "down"
		status.Problems = append(status.Problems, "MollySocket doesn't answer, so no wake-ups are sent.")
	}
	if pushes.LastFailure != nil && (pushes.LastSuccess == nil || pushes.LastFailure.After(*pushes.LastSuccess)) {
		if status.Status == "ok" {
			status.Status = "degraded"
		}
		status.Problems = append(status.Problems, "Apple rejected the latest wake-up: "+pushes.LastError)
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
	bundleID string
	stats    *stats
	relay    *relayProbe
	now      func() time.Time
	sleep    func(time.Duration)
}

func (a *admin) authorized(r *http.Request) bool {
	user, password, ok := r.BasicAuth()
	return ok &&
		subtle.ConstantTimeCompare([]byte(user), []byte("admin")) == 1 &&
		subtle.ConstantTimeCompare([]byte(password), []byte(a.password)) == 1
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
		if !a.authorized(r) {
			a.sleep(time.Second)
			w.Header().Set("WWW-Authenticate", `Basic realm="Ivy Push", charset="UTF-8"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.URL.Path == "/admin/status.json" {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(buildStatus(a.relay.status(), a.stats.snapshot(), a.bundleID, a.now()))
			return
		}
		files.ServeHTTP(w, r)
	})
}
