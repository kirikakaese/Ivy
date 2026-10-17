//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class ChatFolderTest: XCTestCase {

    private let contact = ChatFolderChat(threadId: "contact", isGroup: false, isUnread: false, isMuted: false)
    private let unreadContact = ChatFolderChat(threadId: "unread", isGroup: false, isUnread: true, isMuted: false)
    private let mutedGroup = ChatFolderChat(threadId: "muted", isGroup: true, isUnread: true, isMuted: true)
    private let group = ChatFolderChat(threadId: "group", isGroup: true, isUnread: false, isMuted: false)

    func testAllChatsContainsEverything() {
        let folder = ChatFolder(kind: .allChats, name: "", showOnlyUnread: true, showMutedChats: false)
        for chat in [contact, unreadContact, mutedGroup, group] {
            XCTAssertTrue(folder.contains(chat), chat.threadId)
        }
    }

    func testIncludedChats() {
        let folder = ChatFolder(name: "Family", includedThreadIds: ["contact", "group"])
        XCTAssertTrue(folder.contains(contact))
        XCTAssertTrue(folder.contains(group))
        XCTAssertFalse(folder.contains(unreadContact))
    }

    func testChatTypesAndExclusions() {
        let groups = ChatFolder(name: "Groups", includeAllGroupChats: true, excludedThreadIds: ["group"])
        XCTAssertTrue(groups.contains(mutedGroup))
        XCTAssertFalse(groups.contains(group))
        XCTAssertFalse(groups.contains(contact))

        let individual = ChatFolder(name: "1:1", includeAllIndividualChats: true)
        XCTAssertTrue(individual.contains(contact))
        XCTAssertFalse(individual.contains(group))
    }

    func testOnlyUnreadAndMuted() {
        let folder = ChatFolder(
            name: "Unread",
            showOnlyUnread: true,
            showMutedChats: false,
            includeAllIndividualChats: true,
            includeAllGroupChats: true,
        )
        XCTAssertTrue(folder.contains(unreadContact))
        XCTAssertFalse(folder.contains(contact))
        XCTAssertFalse(folder.contains(mutedGroup))
    }

    func testUnreadCounts() {
        let groups = ChatFolder(name: "Groups", includeAllGroupChats: true)
        let individual = ChatFolder(name: "1:1", includeAllIndividualChats: true)
        let counts = ChatFolderChats.unreadCounts(folders: [groups, individual], chats: [contact, unreadContact, mutedGroup, group])
        XCTAssertEqual(counts[groups.id], 1)
        XCTAssertEqual(counts[individual.id], 1)
    }

    func testNewIdsAreSixteenBytes() {
        XCTAssertEqual(ChatFolder.newId().count, 16)
        XCTAssertNotEqual(ChatFolder.newId(), ChatFolder.newId())
    }
}
