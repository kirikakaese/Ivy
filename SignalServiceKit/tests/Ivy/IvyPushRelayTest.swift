//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import UserNotifications
import XCTest

@testable import SignalServiceKit

final class IvyPushRelayTest: XCTestCase {

    func testRelayAddress() {
        XCTAssertEqual(IvyPushRelay.relayURL(from: " relay.example.com/ ")?.absoluteString, "https://relay.example.com")
        XCTAssertEqual(IvyPushRelay.relayURL(from: "https://relay.example.com:8443/molly")?.absoluteString, "https://relay.example.com:8443/molly")
        XCTAssertNil(IvyPushRelay.relayURL(from: "http://relay.example.com"))
        XCTAssertNil(IvyPushRelay.relayURL(from: "https://relay.example.com/?x=1"))
        XCTAssertNil(IvyPushRelay.relayURL(from: ""))
    }

    func testStatusPage() {
        XCTAssertEqual(
            IvyPushRelay.statusPageURL(for: URL(string: "https://relay.example.com")!).absoluteString,
            "https://relay.example.com/status/",
        )
    }

    func testEndpointPointsAtGateway() {
        XCTAssertEqual(
            IvyPushRelay.endpoint(forToken: "ab12", sandbox: false),
            "http://ivy-gateway:8080/apns/ab12",
        )
        XCTAssertEqual(
            IvyPushRelay.endpoint(forToken: "ab12", sandbox: true),
            "http://ivy-gateway:8080/apns/ab12?sandbox=1",
        )
    }

    func testThrowawayKeysAreSignedByTheAccount() throws {
        let identity = IdentityKeyPair.generate()
        let bundle = IvyPushRelay.throwawayKeys(.aci, signedBy: identity)
        XCTAssertTrue(try identity.publicKey.verifySignature(
            message: bundle.signedPreKey.publicKey().serialize(),
            signature: bundle.signedPreKey.signature,
        ))
        XCTAssertTrue(try identity.publicKey.verifySignature(
            message: bundle.lastResortPreKey.publicKey().serialize(),
            signature: bundle.lastResortPreKey.signature,
        ))
    }

    func testWakeCaptureTakesOnlyTheFirstMessage() {
        let capture = IvyWakeCapture()
        let first = UNMutableNotificationContent()
        first.body = "first"
        let second = UNMutableNotificationContent()
        second.body = "second"

        XCTAssertFalse(capture.take(first), "nothing is captured outside a wake-up")
        capture.begin()
        XCTAssertTrue(capture.take(first))
        XCTAssertFalse(capture.take(second), "later messages are posted as usual")
        XCTAssertEqual(capture.end()?.body, "first")
        XCTAssertNil(capture.end())
        XCTAssertFalse(capture.take(second), "capturing ends with the wake-up")
    }
}
