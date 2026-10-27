// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"bufio"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// relayStatus is what MollySocket reports about itself.
type relayStatus struct {
	Reachable     bool   `json:"reachable"`
	Version       string `json:"version,omitempty"`
	Connections   int64  `json:"connections"`
	Forbidden     int64  `json:"forbidden"`
	Messages      int64  `json:"messages"`
	Pushes        int64  `json:"pushes"`
	Reconnections int64  `json:"reconnections"`
}

type relayProbe struct {
	baseURL string
	client  *http.Client
}

func newRelayProbe(baseURL string) *relayProbe {
	return &relayProbe{baseURL: strings.TrimRight(baseURL, "/"), client: &http.Client{Timeout: 3 * time.Second}}
}

func (p *relayProbe) status() relayStatus {
	var status relayStatus
	resp, err := p.client.Get(p.baseURL + "/discover")
	if err != nil {
		return status
	}
	var discover struct {
		MollySocket struct {
			Version string `json:"version"`
		} `json:"mollysocket"`
	}
	err = json.NewDecoder(resp.Body).Decode(&discover)
	resp.Body.Close()
	if err != nil || resp.StatusCode != http.StatusOK {
		return status
	}
	status.Reachable = true
	status.Version = discover.MollySocket.Version

	resp, err = p.client.Get(p.baseURL + "/metrics")
	if err != nil {
		return status
	}
	defer resp.Body.Close()
	metrics := parseMetrics(bufio.NewScanner(resp.Body))
	status.Connections = metrics["mollysocket_connections"]
	status.Forbidden = metrics["mollysocket_forbiddens"]
	status.Messages = metrics["mollysocket_messages"]
	status.Pushes = metrics["mollysocket_pushs"]
	status.Reconnections = metrics["mollysocket_reconnections"]
	return status
}

// parseMetrics reads plain metric lines ("name value") in the Prometheus
// text format.
func parseMetrics(scanner *bufio.Scanner) map[string]int64 {
	values := map[string]int64{}
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 || strings.Contains(fields[0], "{") {
			continue
		}
		if value, err := strconv.ParseFloat(fields[1], 64); err == nil {
			values[fields[0]] = int64(value)
		}
	}
	return values
}
