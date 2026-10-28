// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

const (
	eventLimit   = 100
	hoursKept    = 7 * 24
	daysKept     = 90
	deviceMaxAge = 30 * 24 * time.Hour
)

// Event kinds.
const (
	eventSent         = "sent"
	eventFailed       = "failed"
	eventUnregistered = "unregistered"
)

type event struct {
	Time   time.Time `json:"time"`
	Kind   string    `json:"kind"`
	Device string    `json:"device"`
	Detail string    `json:"detail,omitempty"`
}

// dayHealth counts the minutes of a day (UTC) by the relay's status.
type dayHealth struct {
	OK          int `json:"ok"`
	Maintenance int `json:"maintenance,omitempty"`
	Degraded    int `json:"degraded"`
	Down        int `json:"down"`
}

func (d dayHealth) minutes() int { return d.OK + d.Maintenance + d.Degraded + d.Down }

// status sums up a day for the public history: a few minutes down make it
// a bad day, shorter trouble a degraded one.
func (d dayHealth) status() string {
	switch {
	case d.Down >= 5:
		return "down"
	case d.Down > 0 || d.Degraded >= 5:
		return "degraded"
	case d.Maintenance >= 5:
		return "maintenance"
	case d.minutes() > 0:
		return "ok"
	default:
		return "none"
	}
}

type hourCounts struct {
	Sent         int `json:"sent"`
	Failed       int `json:"failed"`
	Unregistered int `json:"unregistered"`
}

// stats keeps what the admin page shows: counts per hour, totals, when each
// device was last woken and the latest events. Devices are recorded as a
// short hash of their push token, never the token itself.
type stats struct {
	mu   sync.Mutex
	path string
	now  func() time.Time

	Since       time.Time             `json:"since"`
	Hours       map[int64]*hourCounts `json:"hours"`
	TotalSent   int64                 `json:"totalSent"`
	TotalFailed int64                 `json:"totalFailed"`
	LastSuccess time.Time             `json:"lastSuccess"`
	LastFailure time.Time             `json:"lastFailure"`
	LastError   string                `json:"lastError"`
	Devices     map[string]time.Time  `json:"devices"`
	Days        map[string]*dayHealth `json:"days"`
	Events      []event               `json:"events"`
	Latencies   []latencySample       `json:"latencies"`
	started     time.Time
	dirty       bool
}

func newStats(path string, now func() time.Time) *stats {
	s := &stats{
		path:    path,
		now:     now,
		Since:   now(),
		Hours:   map[int64]*hourCounts{},
		Devices: map[string]time.Time{},
		Days:    map[string]*dayHealth{},
		started: now(),
	}
	if path == "" {
		return s
	}
	if data, err := os.ReadFile(path); err == nil {
		var saved stats
		if json.Unmarshal(data, &saved) == nil {
			s.Since = saved.Since
			s.TotalSent, s.TotalFailed = saved.TotalSent, saved.TotalFailed
			s.LastSuccess, s.LastFailure, s.LastError = saved.LastSuccess, saved.LastFailure, saved.LastError
			s.Events = saved.Events
			s.Latencies = saved.Latencies
			if saved.Hours != nil {
				s.Hours = saved.Hours
			}
			if saved.Devices != nil {
				s.Devices = saved.Devices
			}
			if saved.Days != nil {
				s.Days = saved.Days
			}
		}
	}
	return s
}

func deviceID(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])[:8]
}

// latencySample is how long Apple took to accept one wake-up.
type latencySample struct {
	Time time.Time `json:"t"`
	Ms   float64   `json:"ms"`
}

const latencyKept = 2000

// record notes the outcome of one wake-up and, if Apple accepted it, how
// long that took.
func (s *stats) record(token string, err error, took time.Duration) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if err == nil {
		s.Latencies = append(s.Latencies, latencySample{Time: now, Ms: float64(took.Microseconds()) / 1000})
		if len(s.Latencies) > latencyKept {
			s.Latencies = s.Latencies[len(s.Latencies)-latencyKept:]
		}
	}
	hour := now.Truncate(time.Hour).Unix()
	counts := s.Hours[hour]
	if counts == nil {
		counts = &hourCounts{}
		s.Hours[hour] = counts
	}
	e := event{Time: now, Device: deviceID(token)}
	switch {
	case err == nil:
		counts.Sent++
		s.TotalSent++
		s.LastSuccess = now
		s.Devices[e.Device] = now
		e.Kind = eventSent
	case errors.Is(err, errUnregistered):
		counts.Unregistered++
		delete(s.Devices, e.Device)
		e.Kind = eventUnregistered
	default:
		counts.Failed++
		s.TotalFailed++
		s.LastFailure = now
		s.LastError = err.Error()
		e.Kind = eventFailed
		e.Detail = err.Error()
	}
	s.Events = append(s.Events, e)
	if len(s.Events) > eventLimit {
		s.Events = s.Events[len(s.Events)-eventLimit:]
	}
	s.prune(now)
	s.dirty = true
}

func (s *stats) prune(now time.Time) {
	oldest := now.Add(-hoursKept * time.Hour).Truncate(time.Hour).Unix()
	for hour := range s.Hours {
		if hour < oldest {
			delete(s.Hours, hour)
		}
	}
	for device, last := range s.Devices {
		if now.Sub(last) > deviceMaxAge {
			delete(s.Devices, device)
		}
	}
}

const dayFormat = "2006-01-02"

// recordHealth counts one minute with the given status for today.
func (s *stats) recordHealth(status string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now().UTC()
	key := now.Format(dayFormat)
	day := s.Days[key]
	if day == nil {
		day = &dayHealth{}
		s.Days[key] = day
	}
	switch status {
	case statusOK:
		day.OK++
	case statusMaintenance:
		day.Maintenance++
	case statusDegraded:
		day.Degraded++
	case statusDown:
		day.Down++
	default:
		// Unknown minutes don't count either way.
		return
	}
	oldest := now.AddDate(0, 0, -daysKept).Format(dayFormat)
	for key := range s.Days {
		if key < oldest {
			delete(s.Days, key)
		}
	}
	s.dirty = true
}

type dayPoint struct {
	Date   string `json:"date"`
	Status string `json:"status"`
}

// history returns the last 90 days, oldest first.
func (s *stats) history() []dayPoint {
	s.mu.Lock()
	defer s.mu.Unlock()
	today := s.now().UTC()
	points := make([]dayPoint, 0, daysKept)
	for i := daysKept - 1; i >= 0; i-- {
		key := today.AddDate(0, 0, -i).Format(dayFormat)
		status := "none"
		if day := s.Days[key]; day != nil {
			status = day.status()
		}
		points = append(points, dayPoint{Date: key, Status: status})
	}
	return points
}

// uptime is the share of checked minutes in the last n days in which
// nothing was down; nil while no minute was checked.
func (s *stats) uptime(days int) *float64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	today := s.now().UTC()
	up, total := 0, 0
	for i := 0; i < days; i++ {
		if day := s.Days[today.AddDate(0, 0, -i).Format(dayFormat)]; day != nil {
			up += day.OK + day.Maintenance + day.Degraded
			total += day.minutes()
		}
	}
	if total == 0 {
		return nil
	}
	value := float64(up) / float64(total) * 100
	return &value
}

// save writes the stats to disk if they changed.
func (s *stats) save() error {
	s.mu.Lock()
	if !s.dirty || s.path == "" {
		s.mu.Unlock()
		return nil
	}
	data, err := json.Marshal(s)
	s.dirty = false
	s.mu.Unlock()
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

type hourPoint struct {
	Hour time.Time `json:"hour"`
	hourCounts
}

type statsSnapshot struct {
	Since           time.Time   `json:"since"`
	Started         time.Time   `json:"started"`
	Sent24h         int         `json:"sent24h"`
	Failed24h       int         `json:"failed24h"`
	Unregistered24h int         `json:"unregistered24h"`
	TotalSent       int64       `json:"totalSent"`
	TotalFailed     int64       `json:"totalFailed"`
	LastSuccess     *time.Time  `json:"lastSuccess"`
	LastFailure     *time.Time  `json:"lastFailure"`
	LastError       string      `json:"lastError,omitempty"`
	Active24h       int         `json:"active24h"`
	Active7d        int         `json:"active7d"`
	Hourly          []hourPoint `json:"hourly"`
	Events          []event     `json:"events"`
	// WakeMedianMs is the median time Apple took to accept a wake-up in
	// the last 24 hours, with at least minLatencySamples of them.
	WakeMedianMs *float64 `json:"wakeMedianMs"`
	// Acceptance24h is the share of wake-ups Apple accepted in the last
	// 24 hours, with at least minAcceptanceSamples of them.
	Acceptance24h *float64 `json:"acceptance24h"`
}

const (
	minLatencySamples    = 10
	minAcceptanceSamples = 50
)

func optionalTime(t time.Time) *time.Time {
	if t.IsZero() {
		return nil
	}
	return &t
}

func (s *stats) snapshot() statsSnapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	snap := statsSnapshot{
		Since:       s.Since,
		Started:     s.started,
		TotalSent:   s.TotalSent,
		TotalFailed: s.TotalFailed,
		LastSuccess: optionalTime(s.LastSuccess),
		LastFailure: optionalTime(s.LastFailure),
		LastError:   s.LastError,
	}
	current := now.Truncate(time.Hour)
	for i := 23; i >= 0; i-- {
		hour := current.Add(-time.Duration(i) * time.Hour)
		point := hourPoint{Hour: hour}
		if counts := s.Hours[hour.Unix()]; counts != nil {
			point.hourCounts = *counts
		}
		snap.Sent24h += point.Sent
		snap.Failed24h += point.Failed
		snap.Unregistered24h += point.Unregistered
		snap.Hourly = append(snap.Hourly, point)
	}
	for _, last := range s.Devices {
		age := now.Sub(last)
		if age <= 24*time.Hour {
			snap.Active24h++
		}
		if age <= 7*24*time.Hour {
			snap.Active7d++
		}
	}
	var recent []float64
	for _, sample := range s.Latencies {
		if now.Sub(sample.Time) <= 24*time.Hour {
			recent = append(recent, sample.Ms)
		}
	}
	if len(recent) >= minLatencySamples {
		sort.Float64s(recent)
		median := recent[len(recent)/2]
		if len(recent)%2 == 0 {
			median = (recent[len(recent)/2-1] + recent[len(recent)/2]) / 2
		}
		snap.WakeMedianMs = &median
	}
	if attempts := snap.Sent24h + snap.Failed24h; attempts >= minAcceptanceSamples {
		rate := float64(snap.Sent24h) / float64(attempts) * 100
		snap.Acceptance24h = &rate
	}
	// Newest first.
	snap.Events = make([]event, 0, len(s.Events))
	for i := len(s.Events) - 1; i >= 0; i-- {
		snap.Events = append(snap.Events, s.Events[i])
	}
	return snap
}
