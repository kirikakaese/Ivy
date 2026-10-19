//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A chat folder in Signal's official format (storage service
/// `ChatFolderRecord`).
public struct ChatFolder: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Int, Codable, Sendable {
        /// The "All chats" folder. It shows every chat in the inbox.
        case allChats = 1
        case custom = 2
    }

    /// 16 random bytes.
    public let id: Data
    public var kind: Kind
    public var name: String
    /// The order in the folder list, lowest first.
    public var position: UInt32
    public var showOnlyUnread: Bool
    public var showMutedChats: Bool
    public var includeAllIndividualChats: Bool
    public var includeAllGroupChats: Bool
    /// Unique ids of the chats added to the folder.
    public var includedThreadIds: [String]
    /// Unique ids of the chats removed from a folder that includes all 1:1 or
    /// group chats.
    public var excludedThreadIds: [String]
    /// Members received from another device for which this device has no
    /// chat yet, as serialized storage `Recipient`s. They are sent back
    /// unchanged so that editing the folder here doesn't remove them.
    public var unresolvedIncludedRecipients: [Data]
    public var unresolvedExcludedRecipients: [Data]
    /// Set when the folder was deleted. Deleted folders stay in the store so
    /// the deletion reaches the user's other devices.
    public var deletedAtTimestampMs: UInt64?

    public init(
        id: Data = ChatFolder.newId(),
        kind: Kind = .custom,
        name: String,
        position: UInt32 = 0,
        showOnlyUnread: Bool = false,
        showMutedChats: Bool = true,
        includeAllIndividualChats: Bool = false,
        includeAllGroupChats: Bool = false,
        includedThreadIds: [String] = [],
        excludedThreadIds: [String] = [],
        unresolvedIncludedRecipients: [Data] = [],
        unresolvedExcludedRecipients: [Data] = [],
        deletedAtTimestampMs: UInt64? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        self.showOnlyUnread = showOnlyUnread
        self.showMutedChats = showMutedChats
        self.includeAllIndividualChats = includeAllIndividualChats
        self.includeAllGroupChats = includeAllGroupChats
        self.includedThreadIds = includedThreadIds
        self.excludedThreadIds = excludedThreadIds
        self.unresolvedIncludedRecipients = unresolvedIncludedRecipients
        self.unresolvedExcludedRecipients = unresolvedExcludedRecipients
        self.deletedAtTimestampMs = deletedAtTimestampMs
    }

    public static func newId() -> Data {
        return withUnsafeBytes(of: UUID().uuid) { Data($0) }
    }

    public var isDeleted: Bool { deletedAtTimestampMs != nil }

    /// Whether a chat is chosen for this folder, before the unread and muted
    /// filters.
    public func isMember(threadId: String, isGroup: Bool) -> Bool {
        if kind == .allChats {
            return true
        }
        if excludedThreadIds.contains(threadId) {
            return false
        }
        return includedThreadIds.contains(threadId)
            || (includeAllIndividualChats && !isGroup)
            || (includeAllGroupChats && isGroup)
    }

    /// Whether a chat belongs in this folder.
    public func contains(_ chat: ChatFolderChat) -> Bool {
        if kind == .allChats {
            return true
        }
        guard isMember(threadId: chat.threadId, isGroup: chat.isGroup) else {
            return false
        }
        if showOnlyUnread, !chat.isUnread {
            return false
        }
        if !showMutedChats, chat.isMuted {
            return false
        }
        return true
    }
}

/// The facts about a chat that decide whether it belongs in a folder.
public struct ChatFolderChat: Equatable, Sendable {
    public let threadId: String
    public let isGroup: Bool
    public let isUnread: Bool
    public let isMuted: Bool

    public init(threadId: String, isGroup: Bool, isUnread: Bool, isMuted: Bool) {
        self.threadId = threadId
        self.isGroup = isGroup
        self.isUnread = isUnread
        self.isMuted = isMuted
    }
}
