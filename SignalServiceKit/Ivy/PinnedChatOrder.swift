//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Rearranging pinned chats. The order is stored in the account record, so it
/// syncs to all of the user's devices.
public enum PinnedChatOrder {

    /// The full pinned order after the user rearranged the pinned chats they
    /// can see. Pinned chats that are hidden (for example by a folder) keep
    /// their places.
    public static func order(all: [String], visibleInNewOrder visible: [String]) -> [String] {
        let visibleSet = Set(visible)
        var remaining = visible.makeIterator()
        return all.map { visibleSet.contains($0) ? (remaining.next() ?? $0) : $0 }
    }

    /// The pinned order after moving one chat up (negative offset) or down.
    public static func order(all: [String], moving threadId: String, by offset: Int) -> [String] {
        guard let index = all.firstIndex(of: threadId) else {
            return all
        }
        let newIndex = min(max(index + offset, 0), all.count - 1)
        var result = all
        result.remove(at: index)
        result.insert(threadId, at: newIndex)
        return result
    }

    public static func setOrder(_ threadIds: [String], tx: DBWriteTransaction) {
        let threadStore = DependenciesBridge.shared.threadStore
        let threads = threadIds.compactMap { threadStore.fetchThread(uniqueId: $0, tx: tx) }
        DependenciesBridge.shared.pinnedThreadManager.setPinnedThreads(threads, updateStorageService: true, tx: tx)
    }
}
