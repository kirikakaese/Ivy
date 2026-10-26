// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
)

var deviceToken = regexp.MustCompile(`^[0-9a-f]{64,200}$`)

// newHandler serves POST /apns/<token>[?sandbox=1], the push endpoint Ivy
// registers with MollySocket, and GET /health.
func newHandler(sender pushSender) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	mux.HandleFunc("/apns/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		token := strings.ToLower(strings.TrimPrefix(r.URL.Path, "/apns/"))
		if !deviceToken.MatchString(token) {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		body, _ := io.ReadAll(io.LimitReader(r.Body, 4096))
		if !isWakeUp(body) {
			// Registration tests and "connected elsewhere" notices.
			w.WriteHeader(http.StatusCreated)
			return
		}
		err := sender.wake(token, r.URL.Query().Get("sandbox") == "1")
		switch {
		case err == nil:
			w.WriteHeader(http.StatusCreated)
		case errors.Is(err, errUnregistered):
			log.Printf("ivy-gateway: device %s… is no longer registered with Apple", token[:8])
			w.WriteHeader(http.StatusGone)
		default:
			log.Printf("ivy-gateway: push to %s… failed: %v", token[:8], err)
			w.WriteHeader(http.StatusBadGateway)
		}
	})
	return mux
}

// isWakeUp reports whether MollySocket's message announces urgent messages.
func isWakeUp(body []byte) bool {
	var message struct {
		Urgent bool `json:"urgent"`
	}
	return json.Unmarshal(body, &message) == nil && message.Urgent
}
