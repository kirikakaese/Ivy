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

    func testWakeFallbackKeepsTheWakeTextAndIsMarked() {
        let wake = UNMutableNotificationContent()
        wake.body = "You may have new messages"
        wake.userInfo = ["aps": ["mutable-content": 1]]

        let fallback = IvyWakeCapture.fallbackContent(wake, badge: 3)
        XCTAssertEqual(fallback.body, "You may have new messages")
        XCTAssertEqual(fallback.badge, 3)
        XCTAssertEqual(fallback.userInfo[IvyWakeCapture.fallbackKey] as? Bool, true)
        XCTAssertNotNil(fallback.userInfo["aps"])
        XCTAssertNil(wake.userInfo[IvyWakeCapture.fallbackKey], "the original stays unchanged")
    }

    func testQuietRepeatOfAMessage() {
        let message = UNMutableNotificationContent()
        message.title = "Anna"
        message.body = "See you later"
        message.threadIdentifier = "thread-1"
        message.sound = .default
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = "thread-1"
        message.userInfo = userInfo.build()
        XCTAssertTrue(IvyWakeCapture.isMessage(message))

        let quiet = IvyWakeCapture.quietCopy(of: message, badge: 2)
        XCTAssertEqual(quiet.body, "See you later")
        XCTAssertEqual(quiet.threadIdentifier, "thread-1")
        XCTAssertNil(quiet.sound)
        XCTAssertEqual(quiet.interruptionLevel, .passive)
        XCTAssertEqual(quiet.badge, 2)

        let fallback = IvyWakeCapture.fallbackContent(UNNotificationContent(), badge: nil)
        XCTAssertFalse(IvyWakeCapture.isMessage(fallback), "a fallback isn't repeated")
    }

    func testFallbackIsRecognized() {
        let wake = UNMutableNotificationContent()
        wake.userInfo = ["aps": ["alert": ["loc-key": "APN_Message"], "mutable-content": 1]]
        XCTAssertTrue(IvyWakeCapture.isFallback(wake), "an unmarked wake-up")
        XCTAssertTrue(IvyWakeCapture.isFallback(IvyWakeCapture.fallbackContent(UNNotificationContent(), badge: nil)))

        let message = UNMutableNotificationContent()
        var userInfo = AppNotificationUserInfo()
        userInfo.threadId = "thread-1"
        message.userInfo = userInfo.build()
        XCTAssertFalse(IvyWakeCapture.isFallback(message))
    }

    func testFallbackIsQuietRightAfterLeavingIvy() {
        let defaults = UserDefaults(suiteName: "IvyWakeCaptureTest")!
        defaults.removePersistentDomain(forName: "IvyWakeCaptureTest")
        let wake = UNMutableNotificationContent()
        wake.sound = .default
        XCTAssertFalse(IvyWakeCapture.appLeftForegroundRecently(defaults: defaults))
        XCTAssertEqual(IvyWakeCapture.fallbackContent(wake, badge: nil).interruptionLevel, .active)

        IvyWakeCapture.noteAppLeftForeground(defaults: defaults)
        XCTAssertTrue(IvyWakeCapture.appLeftForegroundRecently(defaults: defaults))
        XCTAssertFalse(IvyWakeCapture.appLeftForegroundRecently(defaults: defaults, now: Date().addingTimeInterval(IvyWakeCapture.quietAfterLeaving + 1)))
        let quiet = IvyWakeCapture.fallbackContent(wake, badge: nil, quiet: true)
        XCTAssertEqual(quiet.interruptionLevel, .passive)
        XCTAssertNil(quiet.sound)
    }
}
