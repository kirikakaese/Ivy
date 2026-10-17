//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Stores the user's chat folders and keeps them in sync with the user's
/// other devices through the storage service.
public final class ChatFolderManager {

    public static let shared = ChatFolderManager()

    /// Posted on the main thread after the folders changed, locally or from
    /// another device.
    public static let foldersDidChange = Notification.Name("IvyChatFoldersDidChange")

    /// Signal's limit for custom folders.
    public static let maxCustomFolders = 20

    private let store: KeyValueStore
    private let recordPendingStorageUpdates: ([Data]) -> Void

    public init(
        store: KeyValueStore = KeyValueStore(collection: "IvyChatFolders"),
        recordPendingStorageUpdates: (([Data]) -> Void)? = nil,
    ) {
        self.store = store
        self.recordPendingStorageUpdates = recordPendingStorageUpdates ?? { folderIds in
            let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef as? StorageServiceManagerImpl
            storageServiceManager?.recordPendingUpdates(chatFolderIds: folderIds)
        }
    }

    // MARK: - Reading

    /// The folders in display order, without deleted folders.
    public func folders(tx: DBReadTransaction) -> [ChatFolder] {
        return allFolders(tx: tx)
            .filter { !$0.isDeleted }
            .sorted { ($0.position, $0.id.hexadecimalString) < ($1.position, $1.id.hexadecimalString) }
    }

    /// Every stored folder, including deleted ones.
    public func allFolders(tx: DBReadTransaction) -> [ChatFolder] {
        do {
            return try store.allCodableValues(transaction: tx)
        } catch {
            owsFailDebug("Couldn't read chat folders: \(error)")
            return []
        }
    }

    public func folder(id: Data, tx: DBReadTransaction) -> ChatFolder? {
        return try? store.getCodableValue(forKey: Self.key(id), transaction: tx)
    }

    /// The folder to show in the chat list, or nil for all chats.
    public func selectableFolder(id: Data?, tx: DBReadTransaction) -> ChatFolder? {
        guard let id, let folder = folder(id: id, tx: tx), !folder.isDeleted, folder.kind == .custom else {
            return nil
        }
        return folder
    }

    /// Whether the folder list should be shown: there is at least one folder
    /// besides "All chats".
    public func hasCustomFolders(tx: DBReadTransaction) -> Bool {
        return folders(tx: tx).contains { $0.kind == .custom }
    }

    // MARK: - Changing

    /// Adds or changes a folder. Adding the first folder also adds "All
    /// chats", which every folder list starts with.
    public func save(_ folder: ChatFolder, tx: DBWriteTransaction) {
        var changedIds = [folder.id]
        var folder = folder
        if self.folder(id: folder.id, tx: tx) == nil {
            changedIds += ensureAllChatsFolder(tx: tx)
            folder.position = (folders(tx: tx).map(\.position).max() ?? 0) + 1
        }
        write(folder, tx: tx)
        didChange(changedIds, tx: tx)
    }

    /// Deletes a folder. "All chats" can't be deleted.
    public func delete(id: Data, tx: DBWriteTransaction) {
        guard var folder = folder(id: id, tx: tx), folder.kind == .custom, !folder.isDeleted else {
            return
        }
        folder.deletedAtTimestampMs = Date.ows_millisecondTimestamp()
        folder.includedThreadIds = []
        folder.excludedThreadIds = []
        folder.unresolvedIncludedRecipients = []
        folder.unresolvedExcludedRecipients = []
        write(folder, tx: tx)
        didChange([id], tx: tx)
    }

    /// Puts the folders in the given order. Folders that aren't listed keep
    /// their place after the listed ones.
    public func reorder(_ ids: [Data], tx: DBWriteTransaction) {
        let current = folders(tx: tx)
        let ordered = ids.compactMap { id in current.first { $0.id == id } }
            + current.filter { !ids.contains($0.id) }
        var changedIds = [Data]()
        for (index, var folder) in ordered.enumerated() where folder.position != UInt32(index) {
            folder.position = UInt32(index)
            write(folder, tx: tx)
            changedIds.append(folder.id)
        }
        didChange(changedIds, tx: tx)
    }

    /// Adds a chat to a folder, or takes it back in after it was excluded.
    public func add(threadId: String, toFolder id: Data, tx: DBWriteTransaction) {
        guard var folder = folder(id: id, tx: tx), folder.kind == .custom else {
            return
        }
        folder.excludedThreadIds.removeAll { $0 == threadId }
        if !folder.includedThreadIds.contains(threadId) {
            folder.includedThreadIds.append(threadId)
        }
        write(folder, tx: tx)
        didChange([id], tx: tx)
    }

    /// Removes a chat from a folder. If the folder includes all 1:1 or group
    /// chats, the chat is excluded.
    public func remove(threadId: String, isGroup: Bool, fromFolder id: Data, tx: DBWriteTransaction) {
        guard var folder = folder(id: id, tx: tx), folder.kind == .custom else {
            return
        }
        folder.includedThreadIds.removeAll { $0 == threadId }
        let isIncludedByType = isGroup ? folder.includeAllGroupChats : folder.includeAllIndividualChats
        if isIncludedByType, !folder.excludedThreadIds.contains(threadId) {
            folder.excludedThreadIds.append(threadId)
        }
        write(folder, tx: tx)
        didChange([id], tx: tx)
    }

    // MARK: - Suggested folders

    public enum Suggestion: CaseIterable {
        case unread
        case individualChats
        case groups

        public func makeFolder(name: String) -> ChatFolder {
            switch self {
            case .unread:
                return ChatFolder(name: name, showOnlyUnread: true, includeAllIndividualChats: true, includeAllGroupChats: true)
            case .individualChats:
                return ChatFolder(name: name, includeAllIndividualChats: true)
            case .groups:
                return ChatFolder(name: name, includeAllGroupChats: true)
            }
        }

        /// Whether a folder with the same rules exists already.
        public func isAlreadyAdded(in folders: [ChatFolder]) -> Bool {
            let template = makeFolder(name: "")
            return folders.contains { folder in
                folder.kind == .custom
                    && folder.showOnlyUnread == template.showOnlyUnread
                    && folder.includeAllIndividualChats == template.includeAllIndividualChats
                    && folder.includeAllGroupChats == template.includeAllGroupChats
                    && folder.includedThreadIds.isEmpty
                    && folder.excludedThreadIds.isEmpty
            }
        }
    }

    // MARK: - Storage service

    /// Applies a folder received from another device. Doesn't sync it back.
    func applyRemote(_ folder: ChatFolder, tx: DBWriteTransaction) {
        guard self.folder(id: folder.id, tx: tx) != folder else {
            return
        }
        write(folder, tx: tx)
        notify(tx: tx)
    }

    /// Another device added "All chats" before this one synced its own. Keeps
    /// the received one so there is only one.
    func deleteOtherAllChatsFolders(keeping id: Data, tx: DBWriteTransaction) {
        var changedIds = [Data]()
        for var folder in folders(tx: tx) where folder.kind == .allChats && folder.id != id {
            folder.deletedAtTimestampMs = Date.ows_millisecondTimestamp()
            write(folder, tx: tx)
            changedIds.append(folder.id)
        }
        didChange(changedIds, tx: tx)
    }

    // MARK: - Private

    private static func key(_ id: Data) -> String { id.hexadecimalString }

    private func write(_ folder: ChatFolder, tx: DBWriteTransaction) {
        do {
            try store.setCodable(folder, key: Self.key(folder.id), transaction: tx)
        } catch {
            owsFailDebug("Couldn't save chat folder: \(error)")
        }
    }

    /// Returns the id of "All chats" if it had to be added.
    private func ensureAllChatsFolder(tx: DBWriteTransaction) -> [Data] {
        guard !folders(tx: tx).contains(where: { $0.kind == .allChats }) else {
            return []
        }
        let allChats = ChatFolder(kind: .allChats, name: "", position: 0, includeAllIndividualChats: true, includeAllGroupChats: true)
        write(allChats, tx: tx)
        return [allChats.id]
    }

    private func didChange(_ ids: [Data], tx: DBWriteTransaction) {
        guard !ids.isEmpty else {
            return
        }
        let recordPendingStorageUpdates = self.recordPendingStorageUpdates
        tx.addSyncCompletion {
            recordPendingStorageUpdates(ids)
        }
        notify(tx: tx)
    }

    private func notify(tx: DBWriteTransaction) {
        tx.addSyncCompletion {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.foldersDidChange, object: nil)
            }
        }
    }
}

// MARK: - Chats

public enum ChatFolderChats {

    /// The inbox chats (not archived) with what folders need to know about
    /// them, in chat list order.
    public static func inboxChats(tx: DBReadTransaction) -> [ChatFolderChat] {
        let now = Int64(clamping: Date.ows_millisecondTimestamp())
        let sql = """
        SELECT
            \(threadColumn: .uniqueId),
            \(threadColumn: .recordType) = \(TSThreadType.groupThread.rawValue),
            \(threadColumn: .isMarkedUnread) = 1 OR EXISTS (
                SELECT 1
                FROM \(InteractionRecord.databaseTableName)
                WHERE \(interactionColumn: .threadUniqueId) = \(threadColumnFullyQualified: .uniqueId)
                AND \(InteractionFinder.sqlClauseForUnreadInteractionCounts())
            ),
            \(threadColumn: .mutedUntilTimestamp) > ?
        FROM \(TSThread.databaseTableName)
        WHERE \(threadColumn: .shouldThreadBeVisible) = 1
        AND \(threadColumn: .isArchived) = 0
        ORDER BY
            CASE WHEN \(threadColumn: .lastDraftInteractionRowId) > \(threadColumn: .lastInteractionRowId)
                THEN \(threadColumn: .lastDraftInteractionRowId) ELSE \(threadColumn: .lastInteractionRowId)
            END DESC,
            \(threadColumn: .lastDraftUpdateTimestamp) DESC
        """
        return failIfThrows {
            return try Row.fetchAll(tx.database, sql: sql, arguments: [now]).map { row in
                ChatFolderChat(threadId: row[0], isGroup: row[1], isUnread: row[2], isMuted: row[3])
            }
        }
    }

    /// The chats of `threadIds` that belong in `folder`, in the same order.
    /// Chats in `required` are always kept.
    public static func threadIds(
        _ threadIds: [String],
        in folder: ChatFolder?,
        keeping required: Set<String>,
        tx: DBReadTransaction,
    ) -> [String] {
        guard let folder, folder.kind == .custom else {
            return threadIds
        }
        let members = Set(inboxChats(tx: tx).filter { folder.contains($0) }.map(\.threadId))
        return threadIds.filter { members.contains($0) || required.contains($0) }
    }

    /// The number of chats with unread messages in each folder.
    public static func unreadCounts(folders: [ChatFolder], chats: [ChatFolderChat]) -> [Data: Int] {
        let unreadChats = chats.filter(\.isUnread)
        var result = [Data: Int]()
        for folder in folders {
            result[folder.id] = unreadChats.count(where: { folder.contains($0) })
        }
        return result
    }
}
