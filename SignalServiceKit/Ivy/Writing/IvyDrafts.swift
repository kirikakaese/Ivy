//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// A message the user started in a chat and didn't send.
public struct IvyDraft: Equatable, Sendable {
    public let threadUniqueId: String
    public let text: String
    public let updatedAt: Date
}

/// Unfinished messages across chats, for Home. They are the drafts the
/// chats keep themselves; Ivy only lists them.
public enum IvyDrafts {

    /// Newest first.
    public static func all(limit: Int, tx: DBReadTransaction) -> [IvyDraft] {
        let sql = """
        SELECT * FROM \(TSThread.databaseTableName)
        WHERE messageDraft IS NOT NULL AND TRIM(messageDraft) != ''
        ORDER BY lastDraftUpdateTimestamp DESC
        LIMIT ?
        """
        do {
            return try TSThread.fetchAll(tx.database, sql: sql, arguments: [limit]).compactMap { thread in
                guard let text = thread.messageDraft?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    return nil
                }
                return IvyDraft(
                    threadUniqueId: thread.uniqueId,
                    text: text,
                    updatedAt: Date(millisecondsSince1970: thread.lastDraftUpdateTimestamp),
                )
            }
        } catch {
            owsFailDebug("Couldn't read drafts: \(error.grdbErrorForLogging)")
            return []
        }
    }

    /// Throws a draft away.
    public static func discard(threadUniqueId: String, tx: DBWriteTransaction) {
        guard let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx) else {
            return
        }
        thread.updateWithDraft(draftMessageBody: nil, replyInfo: nil, editTargetTimestamp: nil, transaction: tx)
    }
}
