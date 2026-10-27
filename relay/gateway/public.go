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

// monitor checks the relay once a minute, counts the result into the daily
// history and keeps it for the public status page, so visitors never cause
// checks themselves.
type monitor struct {
	stats    *stats
	relay    *relayProbe
	bundleID string
	now      func() time.Time

	mu     sync.Mutex
	latest *adminStatus
}

func (m *monitor) check() adminStatus {
	status := buildStatus(m.relay.status(), m.stats.snapshot(), m.bundleID, m.now())
	m.stats.recordHealth(status.Status)
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

type publicStatus struct {
	Status  string     `json:"status"`
	Message string     `json:"message"`
	Checked *time.Time `json:"checked"`
	Days    []dayPoint `json:"days"`
}

var publicMessages = map[string]string{
	"ok":       "Instant notifications are working.",
	"degraded": "Notifications may be late: Apple is turning down some wake-ups.",
	"down":     "Instant notifications are down. Ivy still gets messages while it's open and through Background App Refresh.",
	"unknown":  "The first check hasn't finished yet.",
}

// publicView tells visitors whether instant notifications work and how the
// last 90 days went, and nothing about who uses the relay or when.
func (m *monitor) publicView() publicStatus {
	view := publicStatus{Status: "unknown", Days: m.stats.history()}
	m.mu.Lock()
	if m.latest != nil {
		view.Status = m.latest.Status
		checked := m.latest.Checked
		view.Checked = &checked
	}
	m.mu.Unlock()
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
