// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only

// ivy-gateway turns MollySocket's wake-ups into Apple push notifications for
// Ivy. MollySocket posts to /apns/<device token> whenever an urgent message
// waits for the account; the gateway then asks Apple to wake Ivy, whose
// notification service fetches and shows the message.
//
// The gateway sees no message content. Its push endpoint is meant to be
// reachable only from MollySocket, inside the Docker network; the optional
// admin page under /admin/ is password protected.
package main

import (
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"
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
	statsPath := ""
	if config.dataDir != "" {
		statsPath = filepath.Join(config.dataDir, "stats.json")
	}
	stats := newStats(statsPath, time.Now)
	go func() {
		for range time.Tick(time.Minute) {
			if err := stats.save(); err != nil {
				log.Printf("ivy-gateway: can't save stats: %v", err)
			}
		}
	}()

	mux := newHandler(sender, stats)
	(&admin{
		password: config.adminPassword,
		bundleID: config.bundleID,
		stats:    stats,
		relay:    newRelayProbe(config.mollySocketURL),
		now:      time.Now,
		sleep:    time.Sleep,
	}).register(mux)
	if config.adminPassword == "" {
		log.Printf("ivy-gateway: no IVY_ADMIN_PASSWORD, so no admin page")
	}

	log.Printf("ivy-gateway: listening on %s for %s", config.listen, config.bundleID)
	log.Fatal(http.ListenAndServe(config.listen, mux))
}
