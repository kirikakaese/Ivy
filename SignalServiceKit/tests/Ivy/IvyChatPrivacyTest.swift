//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyChatPrivacyTest: XCTestCase {

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!

    func testLockingAndOpening() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let locked = IvyLockedChats(store: { store })
        XCTAssertTrue(locked.isOpen(chat))

        locked.setLocked(true, chat: chat)
        XCTAssertTrue(locked.isLocked(chat))
        XCTAssertFalse(locked.isOpen(chat))

        locked.markOpened(chat)
        XCTAssertTrue(locked.isOpen(chat))
        locked.closeAll()
        XCTAssertFalse(locked.isOpen(chat))

        locked.setLocked(false, chat: chat)
        XCTAssertTrue(locked.isOpen(chat))
    }

    func testLinkPreviewsPerChat() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        XCTAssertFalse(IvyLinkPreviews.areOff(for: chat, store: store))
        IvyLinkPreviews.setOff(true, for: chat, store: store)
        XCTAssertTrue(IvyLinkPreviews.areOff(for: chat, store: store))
        IvyLinkPreviews.setOff(false, for: chat, store: store)
        XCTAssertFalse(IvyLinkPreviews.areOff(for: chat, store: store))
    }

    func testFolderTimerHoldsSettings() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let folderId = Data([3])
        var extras = ChatFolderExtras()
        extras.disappearingSeconds = 86_400
        extras.save(folderId: folderId, comparedTo: ChatFolderExtras(), store: store)
        XCTAssertEqual(ChatFolderExtras.fetch(folderId: folderId, store: store).disappearingSeconds, 86_400)

        var cleared = extras
        cleared.disappearingSeconds = nil
        cleared.save(folderId: folderId, comparedTo: extras, store: store)
        XCTAssertNil(ChatFolderExtras.fetch(folderId: folderId, store: store).disappearingSeconds)
    }
}
