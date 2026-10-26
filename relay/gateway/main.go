// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

// ivy-gateway turns MollySocket's wake-ups into Apple push notifications for
// Ivy. MollySocket posts to /apns/<device token> whenever an urgent message
// waits for the account; the gateway then asks Apple to wake Ivy, whose
// notification service fetches and shows the message.
//
// The gateway sees no message content and is meant to be reachable only from
// MollySocket, inside the Docker network.
package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	config, err := configFromEnvironment(os.Getenv)
	if err != nil {
		log.Fatalf("ivy-gateway: %v", err)
	}
	sender, err := newAPNsSender(config)
	if err != nil {
		log.Fatalf("ivy-gateway: %v", err)
	}
	log.Printf("ivy-gateway: listening on %s for %s", config.listen, config.bundleID)
	log.Fatal(http.ListenAndServe(config.listen, newHandler(sender)))
}
