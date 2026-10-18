//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// The sections of the app: Home, Chats, Calendar and Calls.
public enum IvySection: String, CaseIterable, Sendable {
    case home
    case chats
    case calendar
    case calls
}

/// Settings for Home and navigation. They stay on this device.
public enum IvyHomeSettings {

    private static let store = KeyValueStore(collection: "IvyHome")
    private static let startSectionKey = "startSection"
    private static let importantChatsKey = "importantChats"

    /// The section the app opens with. Chats unless the user chose another.
    public static func startSection(tx: DBReadTransaction) -> IvySection {
        store.getString(startSectionKey, transaction: tx).flatMap(IvySection.init(rawValue:)) ?? .chats
    }

    public static func setStartSection(_ section: IvySection, tx: DBWriteTransaction) {
        store.setString(section.rawValue, key: startSectionKey, transaction: tx)
    }

    /// Chats whose unread messages Home shows as important.
    public static func importantChats(tx: DBReadTransaction) -> [IvyChatReference] {
        (store.getStringArray(importantChatsKey, transaction: tx) ?? []).compactMap(IvyChatReference.init(rawValue:))
    }

    public static func setImportantChats(_ chats: [IvyChatReference], tx: DBWriteTransaction) {
        store.setStringArray(chats.map(\.rawValue), key: importantChatsKey, transaction: tx)
    }
}

/// An unread message that Home shows as important, and why.
public struct IvyImportantMessage: Sendable {

    public enum Reason: Int, Comparable, Sendable {
        case reminder
        case mention
        case reply
        case importantChat
        case pinnedChat

        public static func < (lhs: Reason, rhs: Reason) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let threadUniqueId: String
    public let messageUniqueId: String
    public let timestamp: UInt64
    public let reason: Reason

    public init(threadUniqueId: String, messageUniqueId: String, timestamp: UInt64, reason: Reason) {
        self.threadUniqueId = threadUniqueId
        self.messageUniqueId = messageUniqueId
        self.timestamp = timestamp
        self.reason = reason
    }

    /// One entry per message with its most important reason, newest first.
    public static func merged(_ candidates: [IvyImportantMessage], limit: Int) -> [IvyImportantMessage] {
        var best = [String: IvyImportantMessage]()
        for candidate in candidates {
            if let existing = best[candidate.messageUniqueId], existing.reason <= candidate.reason {
                continue
            }
            best[candidate.messageUniqueId] = candidate
        }
        return Array(best.values.sorted { ($0.timestamp, $0.messageUniqueId) > ($1.timestamp, $1.messageUniqueId) }.prefix(limit))
    }

    /// Chats looked at for replies, pinned and important chats; unread
    /// messages looked at per chat.
    static let maxChats = 200
    static let maxUnreadPerChat = 100

    /// Important unread messages: mentions of the user, replies to the
    /// user, unread messages in pinned and important chats, and messages
    /// whose reminder has fired.
    public static func find(
        importantChats: [IvyChatReference],
        dueReminderMessages: [IvyMessageReference],
        limit: Int,
        tx: DBReadTransaction,
    ) -> [IvyImportantMessage] {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            return []
        }
        var candidates = [IvyImportantMessage]()

        for message in MentionFinder.messagesMentioning(aci: localAci, includeReadMessages: false, tx: tx) {
            candidates.append(IvyImportantMessage(
                threadUniqueId: message.uniqueThreadId,
                messageUniqueId: message.uniqueId,
                timestamp: message.timestamp,
                reason: .mention,
            ))
        }

        for reference in dueReminderMessages {
            if let message = reference.message(tx: tx) {
                candidates.append(IvyImportantMessage(
                    threadUniqueId: message.uniqueThreadId,
                    messageUniqueId: message.uniqueId,
                    timestamp: message.timestamp,
                    reason: .reminder,
                ))
            }
        }

        let pinnedThreadIds = Set(DependenciesBridge.shared.pinnedThreadManager.pinnedThreads(tx: tx).map(\.uniqueId))
        let importantThreadIds = Set(importantChats.compactMap { $0.thread(tx: tx)?.uniqueId })
        var chatsLookedAt = 0
        ThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
            guard chatsLookedAt < maxChats else {
                return
            }
            chatsLookedAt += 1
            let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
            guard finder.unreadCount(transaction: tx) > 0 else {
                return
            }
            let chatReason: Reason? = importantThreadIds.contains(thread.uniqueId)
                ? .importantChat
                : (pinnedThreadIds.contains(thread.uniqueId) ? .pinnedChat : nil)
            var lookedAt = 0
            var cursor = finder.fetchAllUnreadMessages(transaction: tx)
            while lookedAt < maxUnreadPerChat, let unread = try? cursor.next() {
                lookedAt += 1
                guard let message = unread as? TSIncomingMessage else {
                    continue
                }
                if message.quotedMessage?.authorAddress.aci == localAci {
                    candidates.append(IvyImportantMessage(
                        threadUniqueId: thread.uniqueId,
                        messageUniqueId: message.uniqueId,
                        timestamp: message.timestamp,
                        reason: .reply,
                    ))
                } else if let chatReason {
                    candidates.append(IvyImportantMessage(
                        threadUniqueId: thread.uniqueId,
                        messageUniqueId: message.uniqueId,
                        timestamp: message.timestamp,
                        reason: chatReason,
                    ))
                }
            }
        }
        return merged(candidates, limit: limit)
    }
}
