//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class ChatFolderExtrasCacheTest: XCTestCase {

    func testCachedExtrasFollowChanges() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let folderId = Data([1, 2, 3])
        XCTAssertEqual(ChatFolderExtras.fetchAll(store: store), [:])

        let extras = ChatFolderExtras(emoji: "🔔")
        extras.save(folderId: folderId, comparedTo: ChatFolderExtras(), store: store)
        XCTAssertEqual(ChatFolderExtras.fetchAll(store: store)[folderId]?.emoji, "🔔")

        let before = store.generation
        var changed = extras
        changed.rules = ChatFolderRules(mentionsMe: true)
        changed.save(folderId: folderId, comparedTo: extras, store: store)
        XCTAssertGreaterThan(store.generation, before)
        XCTAssertEqual(ChatFolderExtras.fetchAll(store: store)[folderId]?.rules, ChatFolderRules(mentionsMe: true))

        ChatFolderExtras.delete(folderId: folderId, store: store)
        XCTAssertNil(ChatFolderExtras.fetchAll(store: store)[folderId])
    }
}
