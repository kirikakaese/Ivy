// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"bytes"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strconv"
	"sync"
	"time"
)

// errUnregistered means Apple no longer accepts the device token, for
// example because Ivy was deleted.
var errUnregistered = errors.New("device token no longer valid")

type pushSender interface {
	wake(token string, sandbox bool) error
}

type apnsSender struct {
	config config
	key    *ecdsa.PrivateKey
	client *http.Client
	now    func() time.Time

	mu       sync.Mutex
	jwt      string
	jwtIssue time.Time
}

func newAPNsSender(c config) (*apnsSender, error) {
	key, err := parseKey(c.keyPEM)
	if err != nil {
		return nil, err
	}
	return &apnsSender{
		config: c,
		key:    key,
		client: &http.Client{Timeout: 15 * time.Second},
		now:    time.Now,
	}, nil
}

func parseKey(data []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(data)
	if block == nil {
		return nil, errors.New("the push key isn't a .p8 file from Apple")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("can't read the push key: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("the push key isn't an Apple push key (ES256)")
	}
	return key, nil
}

// token returns the provider token, renewed every 40 minutes; Apple accepts
// each for an hour and rejects renewals more often than every 20 minutes.
func (s *apnsSender) token() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if s.jwt != "" && now.Sub(s.jwtIssue) < 40*time.Minute {
		return s.jwt, nil
	}
	encode := base64.RawURLEncoding.EncodeToString
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": s.config.keyID})
	claims, _ := json.Marshal(map[string]any{"iss": s.config.teamID, "iat": now.Unix()})
	signingInput := encode(header) + "." + encode(claims)
	digest := sha256.Sum256([]byte(signingInput))
	r, sig, err := ecdsa.Sign(rand.Reader, s.key, digest[:])
	if err != nil {
		return "", err
	}
	signature := append(fixed32(r), fixed32(sig)...)
	s.jwt = signingInput + "." + encode(signature)
	s.jwtIssue = now
	return s.jwt, nil
}

func fixed32(n *big.Int) []byte {
	out := make([]byte, 32)
	n.FillBytes(out)
	return out
}

// Ivy's notification service replaces the alert with the message it
// fetched. Only if there's nothing new to show, the alert keeps Signal's
// "You may have new messages" (APN_Message), translated in the app.
var wakePayload = []byte(`{"aps":{"alert":{"loc-key":"APN_Message"},"mutable-content":1}}`)

func (s *apnsSender) wake(deviceToken string, sandbox bool) error {
	bearer, err := s.token()
	if err != nil {
		return err
	}
	base := s.config.production
	if sandbox {
		base = s.config.sandbox
	}
	req, err := http.NewRequest(http.MethodPost, base+"/3/device/"+deviceToken, bytes.NewReader(wakePayload))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+bearer)
	req.Header.Set("apns-topic", s.config.bundleID)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-expiration", strconv.FormatInt(s.now().Add(24*time.Hour).Unix(), 10))
	// No collapse ID: Ivy shows a message in place of the wake-up, and a
	// shared ID made each new message replace the one before. Apple keeps
	// only the latest wake-up for an offline phone anyway.
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	var reason struct {
		Reason string `json:"reason"`
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	_ = json.Unmarshal(body, &reason)
	if resp.StatusCode == http.StatusGone || reason.Reason == "BadDeviceToken" || reason.Reason == "Unregistered" {
		return errUnregistered
	}
	return fmt.Errorf("Apple answered %d %s", resp.StatusCode, reason.Reason)
}
