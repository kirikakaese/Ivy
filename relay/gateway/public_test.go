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
	cases := map[dayHealth]string{
		{}:                       "none",
		{OK: 1440}:               "ok",
		{OK: 1437, Degraded: 3}:  "ok",
		{OK: 1400, Degraded: 40}: "degraded",
		{OK: 1438, Down: 2}:      "degraded",
		{OK: 1380, Down: 60}:     "down",
	}
	for day, want := range cases {
		if got := day.status(); got != want {
			t.Errorf("%+v: %s, want %s", day, got, want)
		}
	}
}

func TestHistoryCoversNinetyDays(t *testing.T) {
	now := time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)
	s := newStats("", func() time.Time { return now })
	s.recordHealth("ok")
	s.recordHealth("down")
	history := s.history()
	if len(history) != 90 || history[89].Date != "2026-10-27" || history[89].Status != "degraded" || history[0].Status != "none" {
		t.Fatalf("history ends %+v, starts %+v", history[89], history[0])
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
	stats.record(token, nil)
	m := &monitor{stats: stats, relay: newRelayProbe(molly.URL), bundleID: "io.example.ivy", now: time.Now}
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
	for _, secret := range []string{token, deviceID(token), "1.7.1", "io.example.ivy", "connections", "messages"} {
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
	a := &admin{password: "secret", stats: newStats("", time.Now), relay: newRelayProbe("http://127.0.0.1:1"),
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
