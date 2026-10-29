// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestDayStatus(t *testing.T) {
	cases := []struct {
		day  dayHealth
		want string
	}{
		{dayHealth{}, "none"},
		{dayHealth{OK: 1440}, "ok"},
		{dayHealth{OK: 1437, Degraded: 3}, "ok"},
		{dayHealth{OK: 1400, Degraded: 40}, "degraded"},
		{dayHealth{OK: 1438, Down: 2}, "degraded"},
		{dayHealth{OK: 1380, Down: 60}, "down"},
	}
	for _, c := range cases {
		if got := c.day.status(); got != c.want {
			t.Errorf("%+v: %s, want %s", c.day, got, c.want)
		}
	}
}

func TestHistoryCoversNinetyDays(t *testing.T) {
	now := time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)
	s := newStats("", func() time.Time { return now })
	s.recordHealth("ok")
	s.recordHealth("down")
	history := s.history("")
	if len(history) != 90 || history[89].Date != "2026-10-27" || history[89].Status != "degraded" || history[0].Status != "none" {
		t.Fatalf("history ends %+v, starts %+v", history[89], history[0])
	}
	if history[0].Minutes != nil || history[0].Hours != nil {
		t.Fatalf("a day without data has no minutes: %+v", history[0])
	}
}

func TestHistoryKeepsHoursAndServices(t *testing.T) {
	now := time.Date(2026, 10, 29, 12, 30, 0, 0, time.UTC)
	s := newStats("", func() time.Time { return now })
	services := func(relay, signal string) []componentStatus {
		return []componentStatus{
			{componentInfo: componentInfo{ID: "relay"}, Status: relay},
			{componentInfo: componentInfo{ID: "signal"}, Status: signal},
		}
	}
	for i := 0; i < 10; i++ {
		s.recordHealth(statusOK, services(statusOK, statusOK)...)
	}
	now = now.Add(2 * time.Hour)
	for i := 0; i < 7; i++ {
		s.recordHealth(statusDown, services(statusDown, statusUnknown)...)
	}
	s.recordHealth(statusDegraded, services(statusOK, statusDegraded)...)

	day := s.history("")[89]
	if day.Status != "down" || *day.Minutes != (dayMinutes{OK: 10, Degraded: 1, Down: 7}) {
		t.Fatalf("overall %+v %+v", day, day.Minutes)
	}
	if len(day.Hours) != 1 || day.Hours[0].Hour != 14 || day.Hours[0].Down != 7 || day.Hours[0].Degraded != 1 {
		t.Fatalf("hours %+v", day.Hours)
	}
	relay := s.history("relay")[89]
	if relay.Status != "down" || relay.Minutes.OK != 11 || relay.Minutes.Down != 7 {
		t.Fatalf("relay %+v %+v", relay, relay.Minutes)
	}
	signal := s.history("signal")[89]
	if signal.Status != "ok" || signal.Minutes.OK != 10 || signal.Minutes.Degraded != 1 || signal.Minutes.Down != 0 {
		t.Fatalf("signal: unknown minutes don't count, %+v %+v", signal, signal.Minutes)
	}
	if apple := s.history("apple")[89]; apple.Status != "none" {
		t.Fatalf("apple wasn't checked: %+v", apple)
	}

	// Saved days from before keep working.
	var old dayHealth
	if err := json.Unmarshal([]byte(`{"ok":1440,"degraded":0,"down":0}`), &old); err != nil || old.status() != "ok" {
		t.Fatalf("%v %+v", err, old)
	}
}

func TestPublicStatusRevealsNoUsage(t *testing.T) {
	molly := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/discover" {
			_, _ = w.Write([]byte(`{"mollysocket":{"version":"1.7.1"}}`))
		} else {
			_, _ = w.Write([]byte("mollysocket_connections 7\nmollysocket_messages 99\n"))
		}
	}))
	defer molly.Close()

	stats := newStats("", time.Now)
	stats.record(token, nil, 300*time.Millisecond)
	m := testMonitor(molly.URL, "")
	m.stats = stats
	mux := newHandler(&fakeSender{}, stats)
	m.register(mux)

	get := func(path string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		return rec
	}
	var before publicStatus
	_ = json.Unmarshal(get("/status/status.json").Body.Bytes(), &before)
	if before.Status != "unknown" {
		t.Fatalf("before the first check: %+v", before)
	}

	m.check()
	rec := get("/status/status.json")
	var view publicStatus
	if rec.Code != http.StatusOK || json.Unmarshal(rec.Body.Bytes(), &view) != nil {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	if view.Status != "ok" || view.Message == "" || len(view.Days) != 90 || view.Days[89].Status != "ok" {
		t.Fatalf("view %+v", view)
	}
	body := rec.Body.String()
	for _, secret := range []string{token, deviceID(token), "1.7.1", "io.example.ivy", `"connections"`, `"messages"`, `"sent24h"`, `"active24h"`} {
		if strings.Contains(body, secret) {
			t.Fatalf("public status contains %q: %s", secret, body)
		}
	}
	for _, path := range []string{"/status/", "/status/status.js", "/status/status.css"} {
		if rec := get(path); rec.Code != http.StatusOK {
			t.Fatalf("%s: %d", path, rec.Code)
		}
	}
}

func TestOldRejectionOnQuietRelayIsANote(t *testing.T) {
	now := time.Now()
	success, failure := now.Add(-5*time.Hour), now.Add(-3*time.Hour)
	s := buildStatus(relayStatus{Reachable: true, Connections: 1}, statsSnapshot{LastSuccess: &success, LastFailure: &failure, LastError: "x"}, "id", now)
	if s.Status != "ok" || len(s.Notes) == 0 {
		t.Fatalf("%+v", s)
	}
}

func TestAdminLocksOutAfterFailedLogins(t *testing.T) {
	now := time.Now()
	m := testMonitor("http://127.0.0.1:1", "")
	a := &admin{password: "secret", monitor: m, posts: m.posts,
		now: func() time.Time { return now }, sleep: func(time.Duration) {}}
	mux := http.NewServeMux()
	a.register(mux)
	try := func(password, ip string) int {
		req := httptest.NewRequest(http.MethodGet, "/admin/", nil)
		req.SetBasicAuth("admin", password)
		req.Header.Set("X-Forwarded-For", ip)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec.Code
	}
	for i := 0; i < loginAttempts; i++ {
		if code := try("wrong", "203.0.113.5"); code != http.StatusUnauthorized {
			t.Fatalf("attempt %d: %d", i, code)
		}
	}
	if code := try("secret", "203.0.113.5"); code != http.StatusTooManyRequests {
		t.Fatalf("locked out: %d", code)
	}
	if code := try("secret", "198.51.100.7"); code != http.StatusOK {
		t.Fatalf("other address: %d", code)
	}
	now = now.Add(loginWindow + time.Minute)
	if code := try("secret", "203.0.113.5"); code != http.StatusOK {
		t.Fatalf("after the window: %d", code)
	}
}
