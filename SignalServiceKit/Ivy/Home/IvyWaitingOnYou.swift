//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Questions the user was asked and hasn't answered, for Home. Runs on the
/// device and only looks at the last message of recent chats: in a
/// one-to-one chat any question counts; in a group, only questions that
/// mention the user or reply to them.
public struct IvyWaitingQuestion: Sendable, Equatable {
    public let threadUniqueId: String
    public let messageUniqueId: String
    public let text: String
    public let timestamp: UInt64
}

public enum IvyWaitingOnYou {

    /// Questions older than this no longer count.
    public static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// Chats looked at, most recent first.
    static let maxChats = 100

    /// Questions the user put aside. They stay on this device.
    private static let dismissedStore = KeyValueStore(collection: "IvyWaitingDismissed")

    // MARK: - Questions

    /// Whether a message reads like a question. Question marks inside links
    /// don't count.
    public static func isQuestion(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).filter { word in
            let lowercased = word.lowercased()
            return !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") && !lowercased.hasPrefix("www.")
        }
        return words.contains { word in
            word.contains("?") || word.contains("？") || word.contains("¿")
        }
    }

    /// Whether a question in a chat waits on the user. In groups it must
    /// mention or reply to the user.
    static func counts(
        isGroup: Bool,
        mentionsUser: Bool,
        repliesToUser: Bool,
        text: String,
        sentAt: Date,
        now: Date,
    ) -> Bool {
        guard now.timeIntervalSince(sentAt) <= maxAge, isQuestion(text) else {
            return false
        }
        return !isGroup || mentionsUser || repliesToUser
    }

    // MARK: - Finding

    /// Unanswered questions, newest first. Chats in `excludedThreadIds`
    /// (hidden or snoozed) are skipped.
    public static func find(
        excludedThreadIds: Set<String> = [],
        now: Date = Date(),
        limit: Int,
        tx: DBReadTransaction,
    ) -> [IvyWaitingQuestion] {
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            return []
        }
        var questions = [IvyWaitingQuestion]()
        var chatsLookedAt = 0
        ThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
            guard chatsLookedAt < maxChats else {
                return
            }
            chatsLookedAt += 1
            guard !thread.isNoteToSelf, !excludedThreadIds.contains(thread.uniqueId) else {
                return
            }
            let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
            guard
                let message = finder.mostRecentInteractionForInbox(forChatListSorting: false, transaction: tx) as? TSIncomingMessage,
                let text = message.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else {
                return
            }
            let mentionsUser = message.bodyRanges?.orderedMentions.contains { $0.value == localAci } ?? false
            let repliesToUser = message.quotedMessage?.authorAddress.aci == localAci
            guard counts(
                isGroup: thread.isGroupThread,
                mentionsUser: mentionsUser,
                repliesToUser: repliesToUser,
                text: text,
                sentAt: Date(millisecondsSince1970: message.timestamp),
                now: now,
            ) else {
                return
            }
            guard !dismissedStore.hasValue(message.uniqueId, transaction: tx) else {
                return
            }
            questions.append(IvyWaitingQuestion(
                threadUniqueId: thread.uniqueId,
                messageUniqueId: message.uniqueId,
                text: String(text.prefix(300)),
                timestamp: message.timestamp,
            ))
        }
        return Array(questions.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// Puts a question aside so Home stops showing it.
    public static func dismiss(_ question: IvyWaitingQuestion, tx: DBWriteTransaction) {
        dismissedStore.setUInt64(question.timestamp, key: question.messageUniqueId, transaction: tx)
    }
}
