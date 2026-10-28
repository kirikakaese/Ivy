// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestStatsCountsAndHidesTokens(t *testing.T) {
	now := time.Date(2026, 10, 27, 12, 30, 0, 0, time.UTC)
	s := newStats("", func() time.Time { return now })
	s.record(token, nil, 300*time.Millisecond)
	s.record(token, errors.New("Apple answered 403 InvalidProviderToken"), 0)
	s.record(token, errUnregistered, 0)

	snap := s.snapshot()
	if snap.Sent24h != 1 || snap.Failed24h != 1 || snap.Unregistered24h != 1 {
		t.Fatalf("counts %+v", snap)
	}
	if len(snap.Hourly) != 24 || snap.Hourly[23].Sent != 1 {
		t.Fatalf("hourly %+v", snap.Hourly)
	}
	if snap.Active24h != 0 {
		t.Fatalf("an unregistered device still counts as active: %d", snap.Active24h)
	}
	data, _ := json.Marshal(snap)
	if strings.Contains(string(data), token) {
		t.Fatal("the snapshot contains a push token")
	}
	if snap.Events[0].Kind != eventUnregistered || snap.Events[0].Device != deviceID(token) {
		t.Fatalf("events %+v", snap.Events)
	}
}

func TestStatsSurviveRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stats.json")
	now := time.Now()
	s := newStats(path, func() time.Time { return now })
	s.record(token, nil, 300*time.Millisecond)
	if err := s.save(); err != nil {
		t.Fatal(err)
	}
	again := newStats(path, func() time.Time { return now })
	if snap := again.snapshot(); snap.TotalSent != 1 || snap.Sent24h != 1 || snap.Active24h != 1 {
		t.Fatalf("after reload %+v", snap)
	}
}

func TestStatusRules(t *testing.T) {
	now := time.Now()
	earlier, later := now.Add(-time.Hour), now.Add(-time.Minute)
	up := relayStatus{Reachable: true, Connections: 3}

	if s := buildStatus(up, statsSnapshot{LastSuccess: &later}, "id", now); s.Status != "ok" || len(s.Problems) != 0 {
		t.Fatalf("healthy: %+v", s)
	}
	if s := buildStatus(relayStatus{}, statsSnapshot{}, "id", now); s.Status != "down" {
		t.Fatalf("relay down: %+v", s)
	}
	failing := statsSnapshot{LastSuccess: &earlier, LastFailure: &later, LastError: "Apple answered 403 InvalidProviderToken", Failed24h: 2}
	if s := buildStatus(up, failing, "id", now); s.Status != "degraded" || !strings.Contains(s.Problems[0], "InvalidProviderToken") {
		t.Fatalf("failing: %+v", s)
	}
	recovered := statsSnapshot{LastSuccess: &later, LastFailure: &earlier, Failed24h: 2}
	if s := buildStatus(up, recovered, "id", now); s.Status != "ok" || len(s.Notes) != 1 {
		t.Fatalf("recovered: %+v", s)
	}
}

func TestParseMetrics(t *testing.T) {
	text := "# HELP mollysocket_connections Connections\n# TYPE mollysocket_connections gauge\nmollysocket_connections 4\nmollysocket_pushs 17\nhttp_requests_total{endpoint=\"/\"} 9\n"
	values := parseMetrics(bufio.NewScanner(strings.NewReader(text)))
	if values["mollysocket_connections"] != 4 || values["mollysocket_pushs"] != 17 || len(values) != 2 {
		t.Fatalf("values %v", values)
	}
}

// testMonitor checks a fake MollySocket and, if given, a fake Signal status.
func testMonitor(mollyURL, signalURL string) *monitor {
	return &monitor{
		stats:    newStats("", time.Now),
		relay:    newRelayProbe(mollyURL),
		signal:   newSignalStatus(signalURL, time.Now),
		posts:    newPosts("", time.Now),
		bundleID: "io.example.ivy",
		now:      time.Now,
	}
}

func TestAdminNeedsPassword(t *testing.T) {
	molly := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/discover":
			_, _ = w.Write([]byte(`{"mollysocket":{"version":"1.7.1"}}`))
		case "/metrics":
			_, _ = w.Write([]byte("mollysocket_connections 2\n"))
		}
	}))
	defer molly.Close()

	mux := newHandler(&fakeSender{}, newStats("", time.Now))
	m := testMonitor(molly.URL, "")
	(&admin{
		password: "correct horse", monitor: m, posts: m.posts, now: time.Now, sleep: func(time.Duration) {},
	}).register(mux)

	get := func(path, user, password string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		if user != "" {
			req.SetBasicAuth(user, password)
		}
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}
	if rec := get("/admin/status.json", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no login: %d", rec.Code)
	}
	if rec := get("/admin/status.json", "admin", "wrong"); rec.Code != http.StatusUnauthorized {
		t.Fatalf("wrong password: %d", rec.Code)
	}
	rec := get("/admin/status.json", "admin", "correct horse")
	var status adminStatus
	if rec.Code != http.StatusOK || json.Unmarshal(rec.Body.Bytes(), &status) != nil {
		t.Fatalf("status: %d %s", rec.Code, rec.Body)
	}
	if status.Status != "ok" || status.Relay.Version != "1.7.1" || status.Relay.Connections != 2 {
		t.Fatalf("status %+v", status)
	}
	for _, path := range []string{"/admin/", "/admin/app.js", "/admin/app.css"} {
		if rec := get(path, "admin", "correct horse"); rec.Code != http.StatusOK {
			t.Fatalf("%s: %d", path, rec.Code)
		}
	}
	if !strings.Contains(rec.Header().Get("Content-Security-Policy"), "default-src 'self'") {
		t.Fatal("missing content security policy")
	}
}

func TestNoAdminWithoutPassword(t *testing.T) {
	mux := newHandler(&fakeSender{}, newStats("", time.Now))
	m := testMonitor("http://127.0.0.1:1", "")
	(&admin{monitor: m, posts: m.posts, now: time.Now, sleep: func(time.Duration) {}}).register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/admin/", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status %d", rec.Code)
	}
}
