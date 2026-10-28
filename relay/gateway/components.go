// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"encoding/json"
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
	{ID: "signal", Name: "Signal service", Description: "Signal's servers, which carry all of Ivy's messages and calls. As reported by Signal."},
}

func componentByID(id string) *componentInfo {
	for i := range components {
		if components[i].ID == id {
			return &components[i]
		}
	}
	return nil
}

// signalStatus reads the summary Signal publishes on its status page, in the
// common status page format ({"status":{"indicator","description"}}).
type signalStatus struct {
	url    string
	client *http.Client
	now    func() time.Time

	mu          sync.Mutex
	checked     time.Time
	status      string
	description string
}

const signalCheckInterval = 5 * time.Minute

func newSignalStatus(url string, now func() time.Time) *signalStatus {
	return &signalStatus{url: url, client: &http.Client{Timeout: 5 * time.Second}, now: now, status: statusUnknown}
}

var signalIndicators = map[string]string{
	"none":        statusOK,
	"minor":       statusDegraded,
	"major":       statusDown,
	"critical":    statusDown,
	"maintenance": statusMaintenance,
}

// current returns Signal's status, asking Signal at most every 5 minutes.
func (s *signalStatus) current() (string, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.url == "" {
		return statusUnknown, ""
	}
	now := s.now()
	if !s.checked.IsZero() && now.Sub(s.checked) < signalCheckInterval {
		return s.status, s.description
	}
	s.checked = now
	s.status, s.description = statusUnknown, ""
	resp, err := s.client.Get(s.url)
	if err != nil {
		return s.status, s.description
	}
	defer resp.Body.Close()
	var summary struct {
		Status struct {
			Indicator   string `json:"indicator"`
			Description string `json:"description"`
		} `json:"status"`
	}
	if resp.StatusCode != http.StatusOK || json.NewDecoder(resp.Body).Decode(&summary) != nil {
		return s.status, s.description
	}
	if status, ok := signalIndicators[summary.Status.Indicator]; ok {
		s.status = status
		if len(summary.Status.Description) <= 200 {
			s.description = summary.Status.Description
		}
	}
	return s.status, s.description
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
