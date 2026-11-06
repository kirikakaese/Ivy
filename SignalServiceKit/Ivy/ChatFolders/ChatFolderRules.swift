//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// The rules of a smart folder: it holds every chat that meets all rules
/// that are on, instead of chosen chats. Stored with the folder's extras,
/// so it syncs between Ivy devices only.
public struct ChatFolderRules: Codable, Equatable, Sendable {
    /// Chats with an unread message that mentions the user.
    public var mentionsMe: Bool
    /// Chats with an open task made from one of their messages.
    public var hasOpenTasks: Bool
    /// Chats with a reminder that is due.
    public var hasDueReminder: Bool
    /// Group chats only.
    public var groupsOnly: Bool
    /// Chats whose name contains this text; empty for any name.
    public var nameContains: String

    public init(
        mentionsMe: Bool = false,
        hasOpenTasks: Bool = false,
        hasDueReminder: Bool = false,
        groupsOnly: Bool = false,
        nameContains: String = "",
    ) {
        self.mentionsMe = mentionsMe
        self.hasOpenTasks = hasOpenTasks
        self.hasDueReminder = hasDueReminder
        self.groupsOnly = groupsOnly
        self.nameContains = nameContains
    }

    /// Whether no rule is on; such a folder holds every chat.
    public var isEmpty: Bool {
        !mentionsMe && !hasOpenTasks && !hasDueReminder && !groupsOnly && trimmedName.isEmpty
    }

    private var trimmedName: String {
        nameContains.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a chat meets every rule that is on.
    public func matches(_ chat: ChatFolderChat, facts: ChatFolderFacts) -> Bool {
        if groupsOnly, !chat.isGroup {
            return false
        }
        if mentionsMe, !facts.unreadMentionThreadIds.contains(chat.threadId) {
            return false
        }
        if hasOpenTasks, !facts.openTaskThreadIds.contains(chat.threadId) {
            return false
        }
        if hasDueReminder, !facts.dueReminderThreadIds.contains(chat.threadId) {
            return false
        }
        let name = trimmedName
        if !name.isEmpty {
            guard let chatName = facts.names[chat.threadId] else {
                return false
            }
            return chatName.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return true
    }
}

/// What smart folder rules need to know about the chats, gathered once.
public struct ChatFolderFacts: Equatable, Sendable {
    public var unreadMentionThreadIds: Set<String>
    public var openTaskThreadIds: Set<String>
    public var dueReminderThreadIds: Set<String>
    /// Chat names, only gathered when a rule looks at names.
    public var names: [String: String]

    public init(
        unreadMentionThreadIds: Set<String> = [],
        openTaskThreadIds: Set<String> = [],
        dueReminderThreadIds: Set<String> = [],
        names: [String: String] = [:],
    ) {
        self.unreadMentionThreadIds = unreadMentionThreadIds
        self.openTaskThreadIds = openTaskThreadIds
        self.dueReminderThreadIds = dueReminderThreadIds
        self.names = names
    }

    public static let none = ChatFolderFacts()

    /// Gathers only what `rules` look at.
    public static func load(for rules: [ChatFolderRules], chats: [ChatFolderChat], tx: DBReadTransaction) -> ChatFolderFacts {
        var facts = ChatFolderFacts()
        if rules.contains(where: \.mentionsMe) {
            facts.unreadMentionThreadIds = unreadMentionThreadIds(tx: tx)
        }
        if rules.contains(where: \.hasOpenTasks) {
            let chatsWithTasks = Set(IvyTaskManager.shared.allTasks().filter { !$0.isDone }.compactMap { $0.source?.message.chat })
            facts.openTaskThreadIds = Set(chatsWithTasks.compactMap { $0.thread(tx: tx)?.uniqueId })
        }
        if rules.contains(where: \.hasDueReminder) {
            facts.dueReminderThreadIds = Set(IvyReminderManager.shared.dueThreadIds(tx: tx))
        }
        if rules.contains(where: { !$0.nameContains.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let contactManager = SSKEnvironment.shared.contactManagerRef
            for chat in chats {
                if let thread = TSThread.fetchViaCache(uniqueId: chat.threadId, transaction: tx) {
                    facts.names[chat.threadId] = contactManager.displayName(for: thread, transaction: tx)
                }
            }
        }
        return facts
    }

    /// Chats with an unread message that mentions the user.
    private static func unreadMentionThreadIds(tx: DBReadTransaction) -> Set<String> {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            return []
        }
        let sql = """
        SELECT DISTINCT mention.\(TSMention.CodingKeys.uniqueThreadId.rawValue)
        FROM \(TSMention.databaseTableName) AS mention
        JOIN \(InteractionRecord.databaseTableName) AS interaction
            ON interaction.\(interactionColumn: .uniqueId) = mention.\(TSMention.CodingKeys.uniqueMessageId.rawValue)
        WHERE mention.\(TSMention.CodingKeys.aciString.rawValue) = ?
        AND interaction.\(interactionColumn: .read) = 0
        """
        return failIfThrows {
            Set(try String.fetchAll(tx.database, sql: sql, arguments: [localAci.serviceIdUppercaseString]))
        }
    }
}
