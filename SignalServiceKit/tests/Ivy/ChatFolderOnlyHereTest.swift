//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class ChatFolderOnlyHereTest: XCTestCase {

    private let chats = [
        ChatFolderChat(threadId: "party", isGroup: true, isUnread: true, isMuted: false),
        ChatFolderChat(threadId: "family", isGroup: true, isUnread: false, isMuted: false),
        ChatFolderChat(threadId: "anne", isGroup: false, isUnread: true, isMuted: false),
    ]

    func testChatsOfFoldersShownOnlyThereLeaveAllChats() {
        let party = ChatFolder(name: "Partei", includedThreadIds: ["party"])
        XCTAssertEqual(ChatFolderChats.hiddenFromAllChats(chats, folders: [party]), ["party"])
        XCTAssertEqual(ChatFolderChats.hiddenFromAllChats(chats, folders: []), [])
        // "All chats" itself never hides anything.
        let all = ChatFolder(kind: .allChats, name: "")
        XCTAssertEqual(ChatFolderChats.hiddenFromAllChats(chats, folders: [all]), [])
    }

    func testTheSettingIsKept() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let folderId = ChatFolder.newId()
        var extras = ChatFolderExtras()
        extras.showsOnlyHere = true
        extras.save(folderId: folderId, comparedTo: ChatFolderExtras(), store: store)
        XCTAssertTrue(ChatFolderExtras.fetch(folderId: folderId, store: store).showsOnlyHere)
        var off = extras
        off.showsOnlyHere = false
        off.save(folderId: folderId, comparedTo: extras, store: store)
        XCTAssertFalse(ChatFolderExtras.fetch(folderId: folderId, store: store).showsOnlyHere)
    }
}
