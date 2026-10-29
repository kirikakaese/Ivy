// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"embed"
	"encoding/json"
	"io/fs"
	"net/http"
	"sync"
	"time"
)

//go:embed public
var publicFiles embed.FS

// monitor checks the relay, Apple push delivery and Signal once a minute,
// combines them with the posts written on the admin page, counts the result
// into the daily history and keeps it for the public status page, so
// visitors never cause checks themselves.
type monitor struct {
	stats    *stats
	relay    *relayProbe
	signal   *signalStatus
	posts    *posts
	bundleID string
	now      func() time.Time

	mu        sync.Mutex
	reconnect reconnectWatch
	latest    *adminStatus
}

// evaluate checks everything now without counting it into the history.
func (m *monitor) evaluate() adminStatus {
	now := m.now()
	relay := m.relay.status()
	pushes := m.stats.snapshot()
	status := buildStatus(relay, pushes, m.bundleID, now)

	m.mu.Lock()
	unstable := relay.Reachable && m.reconnect.unstable(now, relay.Reconnections)
	m.mu.Unlock()

	automatic := map[string]componentStatus{}
	switch {
	case !relay.Reachable:
		automatic["relay"] = componentStatus{Status: statusDown, Detail: "MollySocket doesn't answer."}
	case unstable:
		automatic["relay"] = componentStatus{Status: statusDegraded, Detail: "Connections to Signal keep dropping."}
		status.Problems = append(status.Problems, "MollySocket reconnected to Signal 20 or more times in ten minutes.")
	default:
		automatic["relay"] = componentStatus{Status: statusOK}
	}

	latestFailed := pushes.LastFailure != nil && (pushes.LastSuccess == nil || pushes.LastFailure.After(*pushes.LastSuccess))
	switch {
	case pushes.Failed24h >= 10 && pushes.Failed24h >= pushes.Sent24h:
		automatic["apple"] = componentStatus{Status: statusDown, Detail: "Apple turns down most wake-ups."}
	case latestFailed && now.Sub(*pushes.LastFailure) < time.Hour:
		automatic["apple"] = componentStatus{Status: statusDegraded, Detail: "Apple turned down the latest wake-up."}
	default:
		automatic["apple"] = componentStatus{Status: statusOK}
	}

	signal, description := m.signal.current()
	automatic["signal"] = componentStatus{Status: signal, Detail: description}
	if lastErr := m.signal.lastError(); lastErr != "" {
		status.Problems = append(status.Problems, "Signal's chat server didn't answer the relay: "+lastErr)
	}

	active := []post{}
	for _, item := range m.posts.all() {
		if item.active(now) {
			active = append(active, item)
		}
	}
	status.Components = componentStatuses(automatic, active)
	status.Status = overall(status.Components)
	return status
}

// check evaluates and counts the result as one minute of history.
func (m *monitor) check() adminStatus {
	status := m.refresh()
	m.stats.recordHealth(status.Status, status.Components...)
	return status
}

// refresh evaluates and shows the result on the public page right away,
// for example after a post changed, without counting it into the history.
func (m *monitor) refresh() adminStatus {
	status := m.evaluate()
	m.mu.Lock()
	m.latest = &status
	m.mu.Unlock()
	return status
}

func (m *monitor) run() {
	m.check()
	for range time.Tick(time.Minute) {
		m.check()
	}
}

type publicComponent struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Status      string `json:"status"`
	// Detail is only passed on for Signal: reachable and how fast.
	Detail string `json:"detail,omitempty"`
	// Days is the service's own 90-day history.
	Days []dayPoint `json:"days"`
}

type publicMetrics struct {
	Uptime30      *float64 `json:"uptime30"`
	Uptime90      *float64 `json:"uptime90"`
	WakeMedianMs  *float64 `json:"wakeMedianMs"`
	Acceptance24h *float64 `json:"acceptance24h"`
}

type publicPost struct {
	ID         string       `json:"id"`
	Kind       string       `json:"kind"`
	Title      string       `json:"title"`
	Impact     string       `json:"impact,omitempty"`
	Components []string     `json:"components"`
	Starts     *time.Time   `json:"starts,omitempty"`
	Ends       *time.Time   `json:"ends,omitempty"`
	Created    time.Time    `json:"created"`
	Closed     *time.Time   `json:"closed,omitempty"`
	Updates    []postUpdate `json:"updates"`
}

type publicStatus struct {
	Status     string            `json:"status"`
	Message    string            `json:"message"`
	Checked    *time.Time        `json:"checked"`
	Components []publicComponent `json:"components"`
	Metrics    publicMetrics     `json:"metrics"`
	Active     []publicPost      `json:"active"`
	Upcoming   []publicPost      `json:"upcoming"`
	Recent     []publicPost      `json:"recent"`
	Days       []dayPoint        `json:"days"`
	// Marked are the incidents and maintenance of the last 90 days, shown
	// as marks under the days they touched.
	Marked []publicPost `json:"marked"`
}

var publicMessages = map[string]string{
	statusOK:          "Everything is working.",
	statusMaintenance: "Maintenance is under way. Notifications may be late meanwhile.",
	statusDegraded:    "Some parts are slow or partly unavailable. Notifications may be late.",
	statusDown:        "Part of Ivy isn't working right now. Ivy still gets messages while it's open.",
	statusUnknown:     "The first check hasn't finished yet.",
}

const recentPosts = 14 * 24 * time.Hour

func toPublicPost(item post) publicPost {
	names := []string{}
	for _, id := range item.Components {
		if info := componentByID(id); info != nil {
			names = append(names, info.Name)
		}
	}
	return publicPost{
		ID: item.ID, Kind: item.Kind, Title: item.Title, Impact: item.Impact, Components: names,
		Starts: item.Starts, Ends: item.Ends, Created: item.Created, Closed: item.Closed, Updates: item.Updates,
	}
}

// publicView tells visitors how Ivy is doing, and nothing about who uses
// the relay, how many or when.
func (m *monitor) publicView() publicStatus {
	now := m.now()
	view := publicStatus{
		Status:     statusUnknown,
		Days:       m.stats.history(""),
		Components: []publicComponent{},
		Active:     []publicPost{},
		Upcoming:   []publicPost{},
		Recent:     []publicPost{},
		Marked:     []publicPost{},
	}
	m.mu.Lock()
	latest := m.latest
	m.mu.Unlock()
	if latest != nil {
		view.Status = latest.Status
		checked := latest.Checked
		view.Checked = &checked
		for _, c := range latest.Components {
			pc := publicComponent{ID: c.ID, Name: c.Name, Description: c.Description, Status: c.Status, Days: m.stats.history(c.ID)}
			if c.ID == "signal" {
				pc.Detail = c.Detail
			}
			view.Components = append(view.Components, pc)
		}
	}
	snap := m.stats.snapshot()
	view.Metrics = publicMetrics{
		Uptime30:      m.stats.uptime(30),
		Uptime90:      m.stats.uptime(90),
		WakeMedianMs:  snap.WakeMedianMs,
		Acceptance24h: snap.Acceptance24h,
	}
	for _, item := range m.posts.all() {
		if item.Kind != kindNotice && !item.upcoming(now) && (item.Closed == nil || now.Sub(*item.Closed) < daysKept*24*time.Hour) {
			view.Marked = append(view.Marked, toPublicPost(item))
		}
		switch {
		case item.active(now):
			view.Active = append(view.Active, toPublicPost(item))
		case item.upcoming(now):
			view.Upcoming = append(view.Upcoming, toPublicPost(item))
		case item.Kind == kindNotice && item.step() != "resolved":
			// Removed notices disappear; resolved ones stay listed.
		case item.Closed != nil && now.Sub(*item.Closed) < recentPosts:
			view.Recent = append(view.Recent, toPublicPost(item))
		case item.Kind == kindMaintenance && item.Ends != nil && now.Sub(*item.Ends) < recentPosts:
			view.Recent = append(view.Recent, toPublicPost(item))
		}
	}
	view.Message = publicMessages[view.Status]
	return view
}

func (m *monitor) register(mux *http.ServeMux) {
	static, _ := fs.Sub(publicFiles, "public")
	files := http.StripPrefix("/status/", http.FileServer(http.FS(static)))
	mux.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/status/", http.StatusMovedPermanently)
	})
	mux.HandleFunc("/status/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		if r.URL.Path == "/status/status.json" {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Cache-Control", "public, max-age=30")
			w.Header().Set("Access-Control-Allow-Origin", "*")
			_ = json.NewEncoder(w).Encode(m.publicView())
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=300")
		files.ServeHTTP(w, r)
	})
}
