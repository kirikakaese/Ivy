//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What Ivy adds to a chat folder beyond the official format: an emoji, a
/// color, chats pinned in this folder only and the hours its chats may
/// notify. Stored in the Ivy data store,
/// so it syncs between Ivy devices only.
public struct ChatFolderExtras: Equatable, Sendable {
    public var emoji: String?
    public var color: ChatFolderColor?
    /// Chats pinned at the top of this folder, in order.
    public var pinnedChats: [IvyChatReference]
    /// When the folder's chats may notify. Nil: any time.
    public var notificationHours: IvyNotificationHours?
    /// The disappearing messages timer the folder sets on its chats, in
    /// seconds; 0 is off. Nil: each chat keeps its own.
    public var disappearingSeconds: UInt32?

    public init(
        emoji: String? = nil,
        color: ChatFolderColor? = nil,
        pinnedChats: [IvyChatReference] = [],
        notificationHours: IvyNotificationHours? = nil,
        disappearingSeconds: UInt32? = nil,
    ) {
        self.emoji = emoji
        self.color = color
        self.pinnedChats = pinnedChats
        self.notificationHours = notificationHours
        self.disappearingSeconds = disappearingSeconds
    }

    public static let maxPinnedChats = 4

    // MARK: - Store

    static let kind = "folder"

    private enum Field {
        static let emoji = "emoji"
        static let color = "color"
        static let pinnedChats = "pins"
        static let notificationHours = "hours"
        static let disappearingSeconds = "disappear"
    }

    public static func fetch(folderId: Data, store: IvyDataStore?) -> ChatFolderExtras {
        guard let fields = store?.entity(kind: kind, id: folderId.hexadecimalString) else {
            return ChatFolderExtras()
        }
        return ChatFolderExtras(
            emoji: IvyDataStore.decode(String.self, from: fields[Field.emoji]),
            color: IvyDataStore.decode(String.self, from: fields[Field.color]).flatMap(ChatFolderColor.init(rawValue:)),
            pinnedChats: IvyDataStore.decode([IvyChatReference].self, from: fields[Field.pinnedChats]) ?? [],
            notificationHours: IvyDataStore.decode(IvyNotificationHours.self, from: fields[Field.notificationHours]),
            disappearingSeconds: IvyDataStore.decode(UInt32.self, from: fields[Field.disappearingSeconds]),
        )
    }

    public static func fetchAll(store: IvyDataStore?) -> [Data: ChatFolderExtras] {
        guard let store else {
            return [:]
        }
        var result = [Data: ChatFolderExtras]()
        for entityId in store.entities(kind: kind).keys {
            if let id = Data(hex: entityId) {
                result[id] = fetch(folderId: id, store: store)
            }
        }
        return result
    }

    /// Saves the fields that differ from `old`, so that edits on another
    /// device to other fields are kept. A cleared field is saved as nil.
    public func save(folderId: Data, comparedTo old: ChatFolderExtras, store: IvyDataStore?) {
        var fields = [String: String?]()
        if emoji != old.emoji {
            fields.updateValue(emoji.map { IvyDataStore.encode($0) }, forKey: Field.emoji)
        }
        if color != old.color {
            fields.updateValue(color.map { IvyDataStore.encode($0.rawValue) }, forKey: Field.color)
        }
        if pinnedChats != old.pinnedChats {
            fields[Field.pinnedChats] = IvyDataStore.encode(pinnedChats)
        }
        if notificationHours != old.notificationHours {
            fields.updateValue(notificationHours.map { IvyDataStore.encode($0) }, forKey: Field.notificationHours)
        }
        if disappearingSeconds != old.disappearingSeconds {
            fields.updateValue(disappearingSeconds.map { IvyDataStore.encode($0) }, forKey: Field.disappearingSeconds)
        }
        guard !fields.isEmpty else {
            return
        }
        store?.update(kind: Self.kind, entityId: folderId.hexadecimalString, fields: fields)
    }

    public static func delete(folderId: Data, store: IvyDataStore?) {
        store?.delete(kind: kind, entityId: folderId.hexadecimalString)
    }
}

/// The colors a folder can have.
public enum ChatFolderColor: String, CaseIterable, Sendable {
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case gray
}
