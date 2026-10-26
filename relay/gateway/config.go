// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

type config struct {
	listen     string
	bundleID   string
	teamID     string
	keyID      string
	keyPEM     []byte
	production string
	sandbox    string
}

const (
	productionAPNs = "https://api.push.apple.com"
	sandboxAPNs    = "https://api.sandbox.push.apple.com"
)

// configFromEnvironment reads the settings described in relay/README.md.
func configFromEnvironment(getenv func(string) string) (config, error) {
	c := config{
		listen:     getenv("IVY_LISTEN"),
		bundleID:   strings.TrimSpace(getenv("IVY_BUNDLE_ID")),
		teamID:     strings.TrimSpace(getenv("APNS_TEAM_ID")),
		keyID:      strings.TrimSpace(getenv("APNS_KEY_ID")),
		production: productionAPNs,
		sandbox:    sandboxAPNs,
	}
	if c.listen == "" {
		c.listen = ":8080"
	}
	if c.bundleID == "" {
		c.bundleID = "io.github.kirikakaese.ivy"
	}
	var missing []string
	if c.teamID == "" {
		missing = append(missing, "APNS_TEAM_ID")
	}
	if c.keyID == "" {
		missing = append(missing, "APNS_KEY_ID")
	}
	keyFile := getenv("APNS_KEY_FILE")
	if keyFile == "" {
		missing = append(missing, "APNS_KEY_FILE")
	}
	if len(missing) > 0 {
		return c, fmt.Errorf("missing settings: %s", strings.Join(missing, ", "))
	}
	key, err := os.ReadFile(keyFile)
	if err != nil {
		return c, fmt.Errorf("can't read the push key: %w", err)
	}
	if len(key) == 0 {
		return c, errors.New("the push key file is empty")
	}
	c.keyPEM = key
	return c, nil
}
