//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyScheduledMessagesTest: XCTestCase {

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!
    private let sendAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func message(createdBy: UInt32 = 1, claimedBy: UInt32? = nil, claimedAt: Date? = nil) -> IvyScheduledMessage {
        IvyScheduledMessage(
            chat: chat,
            body: Data("hello".utf8),
            previewText: "hello",
            sendAt: sendAt,
            createdBy: createdBy,
            createdAt: sendAt.addingTimeInterval(-3600),
            claimedBy: claimedBy,
            claimedAt: claimedAt,
        )
    }

    func testTheWritingDeviceSendsOnTime() {
        let message = message(createdBy: 1)
        XCTAssertEqual(message.decision(for: 1, now: sendAt.addingTimeInterval(-60)), .wait(until: sendAt))
        XCTAssertEqual(message.decision(for: 1, now: sendAt), .send)
    }

    func testAnotherDeviceTakesOverLater() {
        let message = message(createdBy: 1)
        let takeover = sendAt.addingTimeInterval(IvyScheduledMessage.takeoverDelay)
        XCTAssertEqual(message.decision(for: 2, now: sendAt), .wait(until: takeover))
        XCTAssertEqual(message.decision(for: 2, now: takeover), .claim)
    }

    func testAClaimSettlesBeforeSending() {
        let claimedAt = sendAt.addingTimeInterval(IvyScheduledMessage.takeoverDelay)
        let message = message(createdBy: 1, claimedBy: 2, claimedAt: claimedAt)
        let settled = claimedAt.addingTimeInterval(IvyScheduledMessage.claimSettleTime)
        XCTAssertEqual(message.decision(for: 2, now: claimedAt), .wait(until: settled))
        XCTAssertEqual(message.decision(for: 2, now: settled), .send)
        // A third device leaves it to the claiming device, unless that one
        // never sends.
        let expired = claimedAt.addingTimeInterval(IvyScheduledMessage.claimTimeout)
        XCTAssertEqual(message.decision(for: 3, now: settled), .wait(until: expired))
        XCTAssertEqual(message.decision(for: 3, now: expired), .claim)
        // The writing device still sends if it comes back.
        XCTAssertEqual(message.decision(for: 1, now: settled), .send)
    }

    func testSentMessagesAreLeftAlone() {
        var message = message()
        message.state = .sent
        XCTAssertEqual(message.decision(for: 1, now: sendAt), .none)
    }

    func testStoreRoundTrip() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        var message = message()
        IvyScheduledStore.save(message, store: store)
        XCTAssertEqual(IvyScheduledStore.message(id: message.id, store: store), message)
        XCTAssertEqual(IvyScheduledStore.pending(store: store), [message])

        message.state = .sent
        message.sentAt = sendAt
        IvyScheduledStore.save(message, store: store)
        XCTAssertEqual(IvyScheduledStore.pending(store: store), [])

        IvyScheduledStore.removeOldSent(now: sendAt.addingTimeInterval(IvyScheduledStore.keepSentFor + 1), store: store)
        XCTAssertNil(IvyScheduledStore.message(id: message.id, store: store))
    }
}
