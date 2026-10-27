// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

type recordedWake struct {
	token   string
	sandbox bool
}

type fakeSender struct {
	wakes []recordedWake
	err   error
}

func (f *fakeSender) wake(token string, sandbox bool) error {
	f.wakes = append(f.wakes, recordedWake{token, sandbox})
	return f.err
}

func post(t *testing.T, h http.Handler, path, body string) int {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, path, strings.NewReader(body)))
	return rec.Code
}

func TestUrgentMessageWakesDevice(t *testing.T) {
	sender := &fakeSender{}
	h := newHandler(sender, newStats("", time.Now))
	if code := post(t, h, "/apns/"+token, `{"urgent":true}`); code != http.StatusCreated {
		t.Fatalf("status %d", code)
	}
	if code := post(t, h, "/apns/"+strings.ToUpper(token)+"?sandbox=1", `{"urgent":true}`); code != http.StatusCreated {
		t.Fatalf("status %d", code)
	}
	want := []recordedWake{{token, false}, {token, true}}
	if len(sender.wakes) != 2 || sender.wakes[0] != want[0] || sender.wakes[1] != want[1] {
		t.Fatalf("wakes %v", sender.wakes)
	}
}

func TestOtherMessagesDontWake(t *testing.T) {
	sender := &fakeSender{}
	h := newHandler(sender, newStats("", time.Now))
	for _, body := range []string{`{"test":true}`, `{"code":4409}`, `{"urgent":false}`, `not json`} {
		if code := post(t, h, "/apns/"+token, body); code != http.StatusCreated {
			t.Fatalf("%s: status %d", body, code)
		}
	}
	if len(sender.wakes) != 0 {
		t.Fatalf("unexpected wakes %v", sender.wakes)
	}
}

func TestRejectsBadRequests(t *testing.T) {
	h := newHandler(&fakeSender{}, newStats("", time.Now))
	if code := post(t, h, "/apns/not-a-token", `{"urgent":true}`); code != http.StatusNotFound {
		t.Fatalf("bad token: status %d", code)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/apns/"+token, nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("GET: status %d", rec.Code)
	}
}

func TestUnregisteredTokenIsGone(t *testing.T) {
	h := newHandler(&fakeSender{err: errUnregistered}, newStats("", time.Now))
	if code := post(t, h, "/apns/"+token, `{"urgent":true}`); code != http.StatusGone {
		t.Fatalf("status %d", code)
	}
}

func testKey(t *testing.T) (*ecdsa.PrivateKey, []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return key, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
}

func TestSendsSignedPushToApple(t *testing.T) {
	key, keyPEM := testKey(t)
	var got *http.Request
	var gotBody []byte
	apple := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r
		gotBody, _ = io.ReadAll(r.Body)
	}))
	defer apple.Close()

	sender, err := newAPNsSender(config{
		bundleID: "io.example.ivy", teamID: "TEAM", keyID: "KEY", keyPEM: keyPEM,
		production: apple.URL, sandbox: "http://invalid.invalid",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := sender.wake(token, false); err != nil {
		t.Fatal(err)
	}
	if got.URL.Path != "/3/device/"+token {
		t.Fatalf("path %s", got.URL.Path)
	}
	for header, want := range map[string]string{
		"apns-topic": "io.example.ivy", "apns-push-type": "alert", "apns-priority": "10",
	} {
		if got.Header.Get(header) != want {
			t.Fatalf("%s = %q", header, got.Header.Get(header))
		}
	}
	var payload struct {
		APS struct {
			MutableContent int `json:"mutable-content"`
		} `json:"aps"`
	}
	if err := json.Unmarshal(gotBody, &payload); err != nil || payload.APS.MutableContent != 1 {
		t.Fatalf("payload %s", gotBody)
	}

	// The bearer token is a valid ES256 JWT for the team and key.
	jwt := strings.TrimPrefix(got.Header.Get("authorization"), "bearer ")
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		t.Fatalf("token %q", jwt)
	}
	header, _ := base64.RawURLEncoding.DecodeString(parts[0])
	claims, _ := base64.RawURLEncoding.DecodeString(parts[1])
	if !strings.Contains(string(header), `"kid":"KEY"`) || !strings.Contains(string(claims), `"iss":"TEAM"`) {
		t.Fatalf("header %s claims %s", header, claims)
	}
	sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(&key.PublicKey, digest[:], r, s) {
		t.Fatal("signature doesn't verify")
	}
}

func TestReusesTokenFor40Minutes(t *testing.T) {
	_, keyPEM := testKey(t)
	sender, err := newAPNsSender(config{teamID: "T", keyID: "K", keyPEM: keyPEM})
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1_800_000_000, 0)
	sender.now = func() time.Time { return now }
	first, _ := sender.token()
	now = now.Add(39 * time.Minute)
	if again, _ := sender.token(); again != first {
		t.Fatal("token renewed too early")
	}
	now = now.Add(2 * time.Minute)
	if renewed, _ := sender.token(); renewed == first {
		t.Fatal("token not renewed")
	}
}

func TestAppleRejections(t *testing.T) {
	_, keyPEM := testKey(t)
	status, reason := http.StatusGone, "Unregistered"
	apple := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"reason":"` + reason + `"}`))
	}))
	defer apple.Close()
	sender, _ := newAPNsSender(config{teamID: "T", keyID: "K", keyPEM: keyPEM, production: apple.URL})
	if err := sender.wake(token, false); err != errUnregistered {
		t.Fatalf("410: %v", err)
	}
	status, reason = http.StatusForbidden, "InvalidProviderToken"
	if err := sender.wake(token, false); err == nil || err == errUnregistered {
		t.Fatalf("403: %v", err)
	}
}

func TestConfigNamesMissingSettings(t *testing.T) {
	_, err := configFromEnvironment(func(string) string { return "" })
	if err == nil || !strings.Contains(err.Error(), "APNS_TEAM_ID, APNS_KEY_ID, APNS_KEY_FILE") {
		t.Fatalf("error %v", err)
	}
}
