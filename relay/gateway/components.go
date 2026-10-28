// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

// Statuses, from best to worst. "unknown" means it couldn't be checked and
// doesn't count towards the overall status.
const (
	statusOK          = "ok"
	statusMaintenance = "maintenance"
	statusDegraded    = "degraded"
	statusDown        = "down"
	statusUnknown     = "unknown"
)

var statusRank = map[string]int{statusUnknown: -1, statusOK: 0, statusMaintenance: 1, statusDegraded: 2, statusDown: 3}

func worse(a, b string) string {
	if statusRank[b] > statusRank[a] {
		return b
	}
	return a
}

type componentInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// components are the parts of Ivy the status page reports on.
var components = []componentInfo{
	{ID: "relay", Name: "Ivy Push relay", Description: "Stays connected to Signal for each account and notices new messages."},
	{ID: "apple", Name: "Apple push delivery", Description: "Hands wake-ups to Apple, which delivers them to iPhones and iPads."},
	{ID: "signal", Name: "Signal service", Description: "Signal's servers, which carry all of Ivy's messages and calls. Checked from the relay."},
}

func componentByID(id string) *componentInfo {
	for i := range components {
		if components[i].ID == id {
			return &components[i]
		}
	}
	return nil
}

// signalStatus checks Signal's chat server from the relay: whether it
// answers and how fast. Signal's own status page offers no data to read.
// Any HTTP answer counts as reachable; a server error or a slow answer as
// trouble, and three failed checks in a row as down. Signal's chat server
// uses a certificate from Signal's own authority, which only Signal's apps
// trust, so a TLS answer signed by an unknown authority also counts as
// reachable: the check sends nothing and only wants to know that it answers.
type signalStatus struct {
	url    string
	client *http.Client
	now    func() time.Time

	mu       sync.Mutex
	checked  time.Time
	failures int
	status   string
	detail   string
	lastErr  string
}

const (
	signalCheckInterval = time.Minute
	signalSlow          = 3 * time.Second
	signalDownAfter     = 3
)

func newSignalStatus(url string, now func() time.Time) *signalStatus {
	return &signalStatus{url: url, client: &http.Client{Timeout: 10 * time.Second}, now: now, status: statusUnknown}
}

// lastError is why the latest check failed, for the admin page.
func (s *signalStatus) lastError() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lastErr
}

// current returns Signal's status, checking at most once a minute.
func (s *signalStatus) current() (string, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.url == "" {
		return statusUnknown, ""
	}
	now := s.now()
	if !s.checked.IsZero() && now.Sub(s.checked) < signalCheckInterval {
		return s.status, s.detail
	}
	s.checked = now
	started := time.Now()
	resp, err := s.client.Get(s.url)
	took := time.Since(started)
	var unknownAuthority x509.UnknownAuthorityError
	if err != nil && errors.As(err, &unknownAuthority) {
		s.failures, s.lastErr = 0, ""
		s.status, s.detail = statusOK, fmt.Sprintf("reachable, %d ms", took.Milliseconds())
		if took >= signalSlow {
			s.status, s.detail = statusDegraded, fmt.Sprintf("slow, %.1f s", took.Seconds())
		}
		return s.status, s.detail
	}
	if err != nil {
		s.lastErr = err.Error()
		s.failures++
		s.detail = "not answering"
		if s.failures >= signalDownAfter {
			s.status = statusDown
		} else if s.status == statusUnknown || s.status == statusOK {
			s.status = statusDegraded
		}
		return s.status, s.detail
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	resp.Body.Close()
	s.failures, s.lastErr = 0, ""
	switch {
	case resp.StatusCode >= 500:
		s.status, s.detail = statusDegraded, fmt.Sprintf("answering with errors (%d)", resp.StatusCode)
	case took >= signalSlow:
		s.status, s.detail = statusDegraded, fmt.Sprintf("slow, %.1f s", took.Seconds())
	default:
		s.status, s.detail = statusOK, fmt.Sprintf("reachable, %d ms", took.Milliseconds())
	}
	return s.status, s.detail
}

// reconnectWatch notices when MollySocket keeps losing its connections to
// Signal: many reconnections within ten minutes.
type reconnectWatch struct {
	samples []reconnectSample
}

type reconnectSample struct {
	time  time.Time
	count int64
}

const (
	reconnectWindow = 10 * time.Minute
	reconnectLimit  = 20
)

func (w *reconnectWatch) unstable(now time.Time, count int64) bool {
	if n := len(w.samples); n > 0 && count < w.samples[n-1].count {
		// MollySocket restarted and its counter began again.
		w.samples = nil
	}
	w.samples = append(w.samples, reconnectSample{now, count})
	for len(w.samples) > 1 && now.Sub(w.samples[0].time) > reconnectWindow {
		w.samples = w.samples[1:]
	}
	return count-w.samples[0].count >= reconnectLimit
}

type componentStatus struct {
	componentInfo
	Status string `json:"status"`
	// Automatic is what the checks found, before posts on the admin page.
	Automatic string `json:"automatic"`
	Detail    string `json:"detail,omitempty"`
}

// componentStatuses combines the automatic checks with active posts.
func componentStatuses(automatic map[string]componentStatus, active []post) []componentStatus {
	out := make([]componentStatus, 0, len(components))
	for _, info := range components {
		status := automatic[info.ID]
		status.componentInfo = info
		status.Automatic = status.Status
		for _, item := range active {
			effect := item.effect()
			if effect == "" {
				continue
			}
			for _, id := range item.Components {
				if id == info.ID {
					if status.Status == statusUnknown {
						status.Status = effect
					} else {
						status.Status = worse(status.Status, effect)
					}
				}
			}
		}
		out = append(out, status)
	}
	return out
}

func overall(statuses []componentStatus) string {
	result := statusOK
	known := false
	for _, s := range statuses {
		if s.Status == statusUnknown {
			continue
		}
		known = true
		result = worse(result, s.Status)
	}
	if !known {
		return statusUnknown
	}
	return result
}
