// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Kinds of posts on the status page.
const (
	kindIncident    = "incident"
	kindMaintenance = "maintenance"
	kindNotice      = "notice"
)

// Impact of an incident on the components it names.
const (
	impactMinor = "minor"
	impactMajor = "major"
)

// Steps of a post, shown with each update.
var postSteps = map[string][]string{
	kindIncident:    {"investigating", "identified", "monitoring", "resolved"},
	kindMaintenance: {"scheduled", "in_progress", "completed"},
	kindNotice:      {"posted", "removed"},
}

// finalSteps end a post.
var finalSteps = map[string]bool{"resolved": true, "completed": true, "removed": true}

type postUpdate struct {
	Time    time.Time `json:"time"`
	Step    string    `json:"step"`
	Message string    `json:"message"`
}

// post is an incident, a maintenance window or a notice, written on the
// admin page and shown on the public status page.
type post struct {
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

func (p *post) step() string {
	if len(p.Updates) == 0 {
		return ""
	}
	return p.Updates[len(p.Updates)-1].Step
}

// active reports whether the post affects the page now. A maintenance
// window is active from its start until its end or until it is completed.
func (p *post) active(now time.Time) bool {
	if p.Closed != nil {
		return false
	}
	if p.Kind == kindMaintenance {
		if p.Starts != nil && now.Before(*p.Starts) {
			return false
		}
		if p.Ends != nil && !now.Before(*p.Ends) {
			return false
		}
	}
	return true
}

// upcoming reports whether a maintenance window is still ahead.
func (p *post) upcoming(now time.Time) bool {
	return p.Kind == kindMaintenance && p.Closed == nil && p.Starts != nil && now.Before(*p.Starts)
}

// effect is the status a post gives the components it names.
func (p *post) effect() string {
	switch p.Kind {
	case kindIncident:
		if p.Impact == impactMajor {
			return statusDown
		}
		if p.Impact == impactMinor {
			return statusDegraded
		}
	case kindMaintenance:
		return statusMaintenance
	}
	return ""
}

type posts struct {
	mu   sync.Mutex
	path string
	now  func() time.Time
	list []*post
}

const postsKept = 90 * 24 * time.Hour

func newPosts(path string, now func() time.Time) *posts {
	p := &posts{path: path, now: now}
	if path != "" {
		if data, err := os.ReadFile(path); err == nil {
			_ = json.Unmarshal(data, &p.list)
		}
	}
	return p
}

var errInvalidPost = errors.New("invalid post")

func newID() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func validStep(kind, step string) bool {
	for _, s := range postSteps[kind] {
		if s == step {
			return true
		}
	}
	return false
}

// postInput is what the admin page sends to create a post.
type postInput struct {
	Kind       string     `json:"kind"`
	Title      string     `json:"title"`
	Impact     string     `json:"impact"`
	Components []string   `json:"components"`
	Message    string     `json:"message"`
	Starts     *time.Time `json:"starts"`
	Ends       *time.Time `json:"ends"`
}

func (p *posts) create(in postInput) (*post, error) {
	in.Title = strings.TrimSpace(in.Title)
	in.Message = strings.TrimSpace(in.Message)
	if postSteps[in.Kind] == nil || in.Title == "" || len(in.Title) > 120 || len(in.Message) > 2000 {
		return nil, errInvalidPost
	}
	var components []string
	for _, id := range in.Components {
		if componentByID(id) != nil {
			components = append(components, id)
		}
	}
	now := p.now()
	created := &post{ID: newID(), Kind: in.Kind, Title: in.Title, Components: components, Created: now}
	switch in.Kind {
	case kindIncident:
		if in.Impact != impactMinor && in.Impact != impactMajor {
			in.Impact = impactMinor
		}
		created.Impact = in.Impact
		created.Updates = []postUpdate{{Time: now, Step: "investigating", Message: in.Message}}
	case kindMaintenance:
		if in.Starts == nil || in.Ends == nil || !in.Ends.After(*in.Starts) {
			return nil, errInvalidPost
		}
		created.Starts, created.Ends = in.Starts, in.Ends
		created.Updates = []postUpdate{{Time: now, Step: "scheduled", Message: in.Message}}
	case kindNotice:
		created.Components = nil
		created.Updates = []postUpdate{{Time: now, Step: "posted", Message: in.Message}}
	}
	p.mu.Lock()
	p.list = append(p.list, created)
	p.mu.Unlock()
	return created, p.save()
}

// update adds a step to a post; a final step closes it.
func (p *posts) update(id, step, message string) error {
	message = strings.TrimSpace(message)
	if len(message) > 2000 {
		return errInvalidPost
	}
	p.mu.Lock()
	found := p.find(id)
	if found == nil || found.Closed != nil || !validStep(found.Kind, step) {
		p.mu.Unlock()
		return errInvalidPost
	}
	now := p.now()
	found.Updates = append(found.Updates, postUpdate{Time: now, Step: step, Message: message})
	if finalSteps[step] {
		found.Closed = &now
	}
	p.mu.Unlock()
	return p.save()
}

func (p *posts) remove(id string) error {
	p.mu.Lock()
	kept := p.list[:0]
	removed := false
	for _, item := range p.list {
		if item.ID == id {
			removed = true
			continue
		}
		kept = append(kept, item)
	}
	p.list = kept
	p.mu.Unlock()
	if !removed {
		return errInvalidPost
	}
	return p.save()
}

func (p *posts) find(id string) *post {
	for _, item := range p.list {
		if item.ID == id {
			return item
		}
	}
	return nil
}

// all returns copies of the posts, newest first, dropping ones closed more
// than 90 days ago.
func (p *posts) all() []post {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := p.now()
	kept := p.list[:0]
	for _, item := range p.list {
		if item.Closed == nil || now.Sub(*item.Closed) < postsKept {
			kept = append(kept, item)
		}
	}
	p.list = kept
	// Newest first; posts created in the same moment keep their order.
	out := make([]post, 0, len(p.list))
	for i := len(p.list) - 1; i >= 0; i-- {
		copied := *p.list[i]
		copied.Updates = append([]postUpdate{}, p.list[i].Updates...)
		out = append(out, copied)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Created.After(out[j].Created) })
	return out
}

func (p *posts) save() error {
	if p.path == "" {
		return nil
	}
	p.mu.Lock()
	data, err := json.Marshal(p.list)
	p.mu.Unlock()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(p.path), 0o700); err != nil {
		return err
	}
	tmp := p.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, p.path)
}
