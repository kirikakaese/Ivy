// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPostLifecycle(t *testing.T) {
	now := time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC)
	p := newPosts(filepath.Join(t.TempDir(), "posts.json"), func() time.Time { return now })

	incident, err := p.create(postInput{Kind: kindIncident, Title: "Late notifications", Impact: impactMajor, Components: []string{"apple", "nope"}, Message: "Looking into it."})
	if err != nil {
		t.Fatal(err)
	}
	if len(incident.Components) != 1 || incident.Components[0] != "apple" || incident.step() != "investigating" {
		t.Fatalf("incident %+v", incident)
	}
	if !incident.active(now) || incident.effect() != statusDown {
		t.Fatal("a major incident takes its components down")
	}
	if err := p.update(incident.ID, "completed", ""); err == nil {
		t.Fatal("maintenance steps don't apply to incidents")
	}
	if err := p.update(incident.ID, "resolved", "Fixed."); err != nil {
		t.Fatal(err)
	}
	if err := p.update(incident.ID, "monitoring", ""); err == nil {
		t.Fatal("a resolved incident takes no more updates")
	}

	starts, ends := now.Add(time.Hour), now.Add(2*time.Hour)
	if _, err := p.create(postInput{Kind: kindMaintenance, Title: "Server update", Starts: &ends, Ends: &starts}); err == nil {
		t.Fatal("maintenance must end after it starts")
	}
	maintenance, err := p.create(postInput{Kind: kindMaintenance, Title: "Server update", Components: []string{"relay"}, Starts: &starts, Ends: &ends})
	if err != nil {
		t.Fatal(err)
	}
	if maintenance.active(now) || !maintenance.upcoming(now) {
		t.Fatal("maintenance in an hour is upcoming")
	}
	if !maintenance.active(starts.Add(time.Minute)) || maintenance.active(ends) {
		t.Fatal("maintenance is active between start and end")
	}

	if _, err := p.create(postInput{Kind: "rumour", Title: "x"}); err == nil {
		t.Fatal("unknown kinds are refused")
	}
	if _, err := p.create(postInput{Kind: kindNotice, Title: "  "}); err == nil {
		t.Fatal("a title is required")
	}

	reloaded := newPosts(p.path, p.now)
	if all := reloaded.all(); len(all) != 2 || all[0].ID != maintenance.ID {
		t.Fatalf("after reload, newest first: %+v", all)
	}
	if err := reloaded.remove(incident.ID); err != nil || len(reloaded.all()) != 1 {
		t.Fatal("remove")
	}
}

func TestPostsChangeComponents(t *testing.T) {
	automatic := map[string]componentStatus{
		"relay":  {Status: statusOK},
		"apple":  {Status: statusOK},
		"signal": {Status: statusUnknown},
	}
	active := []post{
		{Kind: kindIncident, Impact: impactMinor, Components: []string{"apple"}},
		{Kind: kindMaintenance, Components: []string{"relay"}},
		{Kind: kindNotice},
	}
	got := map[string]string{}
	statuses := componentStatuses(automatic, active)
	for _, s := range statuses {
		got[s.ID] = s.Status
	}
	if got["apple"] != statusDegraded || got["relay"] != statusMaintenance || got["signal"] != statusUnknown {
		t.Fatalf("components %v", got)
	}
	if overall(statuses) != statusDegraded {
		t.Fatalf("overall %s", overall(statuses))
	}
	if overall([]componentStatus{{Status: statusUnknown}}) != statusUnknown {
		t.Fatal("nothing known")
	}
}

func TestSignalStatus(t *testing.T) {
	code := http.StatusNotFound
	delay := time.Duration(0)
	calls := 0
	signal := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		time.Sleep(delay)
		w.WriteHeader(code)
	}))

	now := time.Now()
	s := newSignalStatus(signal.URL, func() time.Time { return now })
	if status, detail := s.current(); status != statusOK || !strings.HasPrefix(detail, "reachable, ") {
		t.Fatalf("any answer counts as reachable: %s %q", status, detail)
	}
	code = http.StatusServiceUnavailable
	if status, _ := s.current(); status != statusOK || calls != 1 {
		t.Fatal("Signal is checked at most once a minute")
	}
	now = now.Add(signalCheckInterval)
	if status, detail := s.current(); status != statusDegraded || !strings.Contains(detail, "503") {
		t.Fatalf("server errors: %s %q", status, detail)
	}

	signal.Close()
	for i := 1; i <= signalDownAfter; i++ {
		now = now.Add(signalCheckInterval)
		status, _ := s.current()
		if i < signalDownAfter && status != statusDegraded {
			t.Fatalf("check %d without answer: %s", i, status)
		}
		if i == signalDownAfter && status != statusDown {
			t.Fatalf("three checks without answer: %s", status)
		}
	}
	if status, _ := newSignalStatus("", time.Now).current(); status != statusUnknown {
		t.Fatal("no address, no status")
	}
}

func TestReconnectWatch(t *testing.T) {
	var w reconnectWatch
	start := time.Now()
	if w.unstable(start, 100) {
		t.Fatal("first sample")
	}
	if w.unstable(start.Add(5*time.Minute), 110) {
		t.Fatal("10 reconnections are fine")
	}
	if !w.unstable(start.Add(9*time.Minute), 125) {
		t.Fatal("25 in ten minutes is unstable")
	}
	if w.unstable(start.Add(25*time.Minute), 126) {
		t.Fatal("calm again")
	}
	if w.unstable(start.Add(26*time.Minute), 3) {
		t.Fatal("a restart resets the counter")
	}
}

func TestMetricsNeedEnoughData(t *testing.T) {
	now := time.Now()
	s := newStats("", func() time.Time { return now })
	for i := 0; i < minLatencySamples-1; i++ {
		s.record(token, nil, time.Duration(100+i)*time.Millisecond)
	}
	if s.snapshot().WakeMedianMs != nil {
		t.Fatal("median needs enough samples")
	}
	s.record(token, nil, 200*time.Millisecond)
	if median := s.snapshot().WakeMedianMs; median == nil || *median < 100 || *median > 200 {
		t.Fatalf("median %v", median)
	}
	if s.snapshot().Acceptance24h != nil {
		t.Fatal("acceptance needs 50 wake-ups")
	}
	for i := 0; i < 39; i++ {
		s.record(token, nil, time.Millisecond)
	}
	s.record(token, errors.New("Apple answered 500"), 0)
	if rate := s.snapshot().Acceptance24h; rate == nil || *rate != 98 {
		t.Fatalf("acceptance %v", rate)
	}

	if s.uptime(30) != nil {
		t.Fatal("no checks yet")
	}
	for i := 0; i < 99; i++ {
		s.recordHealth(statusOK)
	}
	s.recordHealth(statusDown)
	s.recordHealth(statusUnknown)
	if up := s.uptime(30); up == nil || *up != 99 {
		t.Fatalf("uptime %v", up)
	}
}

func TestAdminPostsAPI(t *testing.T) {
	m := testMonitor("http://127.0.0.1:1", "")
	mux := http.NewServeMux()
	(&admin{password: "pw", monitor: m, posts: m.posts, now: time.Now, sleep: func(time.Duration) {}}).register(mux)
	m.register(mux)

	send := func(method, path, body string, headers map[string]string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, "https://push.example"+path, strings.NewReader(body))
		req.SetBasicAuth("admin", "pw")
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec
	}
	sameSite := map[string]string{"Content-Type": "application/json", "Origin": "https://push.example", "Sec-Fetch-Site": "same-origin"}
	incident := `{"kind":"incident","title":"Late notifications","impact":"minor","components":["apple"],"message":"Looking into it."}`

	if rec := send(http.MethodPost, "/admin/posts", incident, map[string]string{"Content-Type": "application/json", "Origin": "https://evil.example", "Sec-Fetch-Site": "cross-site"}); rec.Code != http.StatusForbidden {
		t.Fatalf("cross-site: %d", rec.Code)
	}
	if rec := send(http.MethodPost, "/admin/posts", incident, map[string]string{"Content-Type": "text/plain"}); rec.Code != http.StatusForbidden {
		t.Fatalf("form post: %d", rec.Code)
	}
	rec := send(http.MethodPost, "/admin/posts", incident, sameSite)
	var created post
	if rec.Code != http.StatusCreated || json.Unmarshal(rec.Body.Bytes(), &created) != nil {
		t.Fatalf("create: %d %s", rec.Code, rec.Body)
	}

	var view publicStatus
	public := httptest.NewRecorder()
	mux.ServeHTTP(public, httptest.NewRequest(http.MethodGet, "/status/status.json", nil))
	_ = json.Unmarshal(public.Body.Bytes(), &view)
	if len(view.Active) != 1 || view.Active[0].Components[0] != "Apple push delivery" {
		t.Fatalf("public active %+v", view.Active)
	}
	for _, c := range view.Components {
		if c.ID == "apple" && c.Status != statusDegraded {
			t.Fatalf("apple %s", c.Status)
		}
	}

	if rec := send(http.MethodPost, "/admin/posts/"+created.ID+"/updates", `{"step":"resolved","message":"Fixed."}`, sameSite); rec.Code != http.StatusNoContent {
		t.Fatalf("update: %d", rec.Code)
	}
	if rec := send(http.MethodPost, "/admin/posts/"+created.ID+"/updates", `{"step":"resolved"}`, sameSite); rec.Code != http.StatusBadRequest {
		t.Fatalf("closed post: %d", rec.Code)
	}
	if rec := send(http.MethodGet, "/admin/posts", "", nil); rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), `"resolved"`) {
		t.Fatalf("list: %d", rec.Code)
	}
	if rec := send(http.MethodDelete, "/admin/posts/"+created.ID, "", map[string]string{"Sec-Fetch-Site": "cross-site"}); rec.Code != http.StatusForbidden {
		t.Fatalf("cross-site delete: %d", rec.Code)
	}
	if rec := send(http.MethodDelete, "/admin/posts/"+created.ID, "", map[string]string{"Origin": "https://push.example"}); rec.Code != http.StatusNoContent {
		t.Fatalf("delete: %d", rec.Code)
	}
	if len(m.posts.all()) != 0 {
		t.Fatal("deleted")
	}
}

func TestSignalOwnCertificateCountsAsReachable(t *testing.T) {
	// Like Signal's chat server: a certificate from an authority the
	// system doesn't trust.
	signal := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer signal.Close()
	s := newSignalStatus(signal.URL, time.Now)
	if status, detail := s.current(); status != statusOK || !strings.HasPrefix(detail, "reachable, ") || s.lastError() != "" {
		t.Fatalf("%s %q %q", status, detail, s.lastError())
	}
}

func TestNoticesListNoServicesAsEmpty(t *testing.T) {
	p := newPosts("", time.Now)
	if _, err := p.create(postInput{Kind: kindNotice, Title: "New build", Components: []string{"apple"}}); err != nil {
		t.Fatal(err)
	}
	data, _ := json.Marshal(p.all())
	if !strings.Contains(string(data), `"components":[]`) {
		t.Fatalf("notices need an empty list, not null: %s", data)
	}
	// Notices saved before this fix had none.
	p.list[0].Components = nil
	data, _ = json.Marshal(p.all())
	if !strings.Contains(string(data), `"components":[]`) {
		t.Fatalf("old notices: %s", data)
	}
}
