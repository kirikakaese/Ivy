//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyHiddenChatsTest: XCTestCase {

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!
    private let otherChat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000002")!

    func testHidingAndShowing() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let hiddenChats = IvyHiddenChats(store: { store })
        XCTAssertTrue(hiddenChats.isEmpty)

        hiddenChats.hide(chat)
        XCTAssertTrue(hiddenChats.isHidden(chat))
        XCTAssertFalse(hiddenChats.isHidden(otherChat))
        XCTAssertEqual(store.entities(kind: IvyHiddenChats.kind).count, 1)

        hiddenChats.unhide(chat)
        XCTAssertFalse(hiddenChats.isHidden(chat))
        XCTAssertTrue(hiddenChats.isEmpty)
    }

    func testHiddenChatsSyncToOtherDevices() throws {
        let phone = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let mac = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 2 }))
        var changes = [IvyDataChange]()
        phone.onLocalChanges = { changes += $0 }

        IvyHiddenChats(store: { phone }).hide(chat)
        mac.apply(changes)
        XCTAssertTrue(IvyHiddenChats(store: { mac }).isHidden(chat))
    }

    func testRevealingIsOnlyForThisSession() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let hiddenChats = IvyHiddenChats(store: { store })
        XCTAssertFalse(hiddenChats.isRevealed)
        hiddenChats.setRevealed(true)
        XCTAssertTrue(hiddenChats.isRevealed)
        hiddenChats.setRevealed(false)
        XCTAssertFalse(hiddenChats.isRevealed)
    }
}
