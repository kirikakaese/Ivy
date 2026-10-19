//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvySnoozedChatsTest: XCTestCase {

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!
    private let otherChat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000002")!

    func testSnoozingAndEnding() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let snoozed = IvySnoozedChats(store: { store })
        let now = Date(timeIntervalSince1970: 1_000_000)

        snoozed.snooze(chat, until: now.addingTimeInterval(3600))
        snoozed.snooze(otherChat, until: now.addingTimeInterval(60))
        XCTAssertEqual(snoozed.activeSnoozes(now: now).map { $0.chat }, [otherChat, chat])
        XCTAssertNotNil(snoozed.snoozedUntil(chat, now: now))
        XCTAssertTrue(snoozed.ended(now: now).isEmpty)

        let later = now.addingTimeInterval(120)
        XCTAssertEqual(snoozed.activeSnoozes(now: later).map { $0.chat }, [chat])
        XCTAssertEqual(snoozed.ended(now: later), [otherChat])
        XCTAssertNil(snoozed.snoozedUntil(otherChat, now: later))

        snoozed.unsnooze(chat)
        XCTAssertNil(snoozed.snoozedUntil(chat, now: now))
    }

    func testSnoozesSyncToOtherDevices() throws {
        let phone = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let mac = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 2 }))
        var changes = [IvyDataChange]()
        phone.onLocalChanges = { changes += $0 }
        let until = Date(timeIntervalSince1970: 2_000_000)

        IvySnoozedChats(store: { phone }).snooze(chat, until: until)
        mac.apply(changes)
        XCTAssertEqual(IvySnoozedChats(store: { mac }).snoozes[chat], until)
    }
}
