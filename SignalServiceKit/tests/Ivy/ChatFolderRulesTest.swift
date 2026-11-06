//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class ChatFolderRulesTest: XCTestCase {

    private let group = ChatFolderChat(threadId: "g", isGroup: true, isUnread: true, isMuted: false)
    private let person = ChatFolderChat(threadId: "p", isGroup: false, isUnread: false, isMuted: false)
    private let mutedGroup = ChatFolderChat(threadId: "m", isGroup: true, isUnread: true, isMuted: true)

    private let facts = ChatFolderFacts(
        unreadMentionThreadIds: ["g", "p"],
        openTaskThreadIds: ["p"],
        dueReminderThreadIds: ["m"],
        names: ["g": "Kreisvorstand Karlsruhe", "p": "Anne B.", "m": "LJ Karlsruhe"],
    )

    func testAllRulesThatAreOnMustMatch() {
        let mentionedGroups = ChatFolderRules(mentionsMe: true, groupsOnly: true)
        XCTAssertTrue(mentionedGroups.matches(group, facts: facts))
        XCTAssertFalse(mentionedGroups.matches(person, facts: facts))
        XCTAssertFalse(mentionedGroups.matches(mutedGroup, facts: facts))

        XCTAssertTrue(ChatFolderRules(hasOpenTasks: true).matches(person, facts: facts))
        XCTAssertTrue(ChatFolderRules(hasDueReminder: true).matches(mutedGroup, facts: facts))
        XCTAssertFalse(ChatFolderRules(hasDueReminder: true).matches(group, facts: facts))
    }

    func testNameIgnoresCaseAndAccents() {
        let rules = ChatFolderRules(nameContains: " karlsruhe ")
        XCTAssertTrue(rules.matches(group, facts: facts))
        XCTAssertTrue(rules.matches(mutedGroup, facts: facts))
        XCTAssertFalse(rules.matches(person, facts: facts))
        XCTAssertTrue(ChatFolderRules(nameContains: "anne b").matches(person, facts: facts))
    }

    func testNoRulesMatchEverything() {
        XCTAssertTrue(ChatFolderRules().isEmpty)
        XCTAssertTrue(ChatFolderRules().matches(person, facts: .none))
        XCTAssertFalse(ChatFolderRules(nameContains: "x").isEmpty)
    }

    func testMembershipUsesRulesAndFolderFilters() {
        var folder = ChatFolder(name: "Mentions")
        folder.showMutedChats = false
        let membership = ChatFolderMembership(rules: [folder.id: ChatFolderRules(groupsOnly: true)], facts: facts)
        XCTAssertTrue(membership.contains(group, in: folder))
        XCTAssertFalse(membership.contains(person, in: folder))
        XCTAssertFalse(membership.contains(mutedGroup, in: folder), "muted chats stay hidden")

        let counts = ChatFolderChats.unreadCounts(folders: [folder], chats: [group, person, mutedGroup], membership: membership)
        XCTAssertEqual(counts[folder.id], 1)

        // A folder without rules keeps its chosen chats.
        XCTAssertFalse(ChatFolderMembership.plain.contains(group, in: folder))
    }

    func testRulesRoundTripThroughJSON() throws {
        let rules = ChatFolderRules(mentionsMe: true, nameContains: "Kreis")
        let decoded = try JSONDecoder().decode(ChatFolderRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
    }
}
