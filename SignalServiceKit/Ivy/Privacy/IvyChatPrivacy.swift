//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Chats that ask for Face ID, Touch ID or the Ivy passcode before they
/// open. Once opened, a chat stays open until Ivy leaves the screen or
/// locks. Their notifications show the chat's name but not the message.
/// Locked chats sync to all Ivy devices (kind "lockedChat").
public final class IvyLockedChats {

    public static let shared = IvyLockedChats()

    static let kind = "lockedChat"

    private enum Field {
        static let lockedAt = "lockedAt"
    }

    private let lock = NSLock()
    private var cached: Set<IvyChatReference>?
    private var unlocked = Set<IvyChatReference>()

    private let storeProvider: () -> IvyDataStore?

    init(store: @escaping () -> IvyDataStore? = { IvyData.shared?.store }) {
        self.storeProvider = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dataDidChange(_:)),
            name: IvyDataStore.dataDidChange,
            object: nil,
        )
    }

    private var store: IvyDataStore? { storeProvider() }

    @objc
    private func dataDidChange(_ notification: Notification) {
        guard let kinds = notification.userInfo?["kinds"] as? Set<String>, kinds.contains(Self.kind) else {
            return
        }
        reload()
    }

    private func reload() {
        let chats = Set((store?.entities(kind: Self.kind) ?? [:]).keys.compactMap(IvyChatReference.init(rawValue:)))
        lock.lock()
        cached = chats
        lock.unlock()
    }

    /// Safe to call from any thread.
    public var chats: Set<IvyChatReference> {
        lock.lock()
        let value = cached
        lock.unlock()
        if let value {
            return value
        }
        reload()
        lock.lock()
        defer { lock.unlock() }
        return cached ?? []
    }

    public func isLocked(_ chat: IvyChatReference) -> Bool {
        chats.contains(chat)
    }

    public func isLocked(thread: TSThread) -> Bool {
        let chats = self.chats
        guard !chats.isEmpty, let chat = IvyChatReference(thread: thread) else {
            return false
        }
        return chats.contains(chat)
    }

    public func setLocked(_ locked: Bool, chat: IvyChatReference, now: Date = Date()) {
        if locked {
            store?.update(kind: Self.kind, entityId: chat.rawValue, fields: [
                Field.lockedAt: IvyDataStore.encode(UInt64(now.timeIntervalSince1970 * 1000)),
            ])
        } else {
            store?.delete(kind: Self.kind, entityId: chat.rawValue)
        }
        reload()
    }

    // MARK: - Opening

    /// Whether the chat may show right now: not locked, or opened since Ivy
    /// last left the screen.
    public func isOpen(_ chat: IvyChatReference) -> Bool {
        guard isLocked(chat) else {
            return true
        }
        lock.lock()
        defer { lock.unlock() }
        return unlocked.contains(chat)
    }

    /// Call only after the user authenticated.
    public func markOpened(_ chat: IvyChatReference) {
        lock.lock()
        unlocked.insert(chat)
        lock.unlock()
    }

    /// Locks every chat again, when Ivy leaves the screen or locks.
    public func closeAll() {
        lock.lock()
        unlocked.removeAll()
        lock.unlock()
    }
}

/// Chats with link previews turned off when writing. Synced to all Ivy
/// devices (kind "noLinkPreviews").
public enum IvyLinkPreviews {

    static let kind = "noLinkPreviews"

    private enum Field {
        static let off = "off"
    }

    public static func areOff(for chat: IvyChatReference, store: IvyDataStore? = IvyData.shared?.store) -> Bool {
        store?.entity(kind: kind, id: chat.rawValue) != nil
    }

    public static func setOff(_ off: Bool, for chat: IvyChatReference, store: IvyDataStore? = IvyData.shared?.store) {
        if off {
            store?.update(kind: kind, entityId: chat.rawValue, fields: [Field.off: IvyDataStore.encode(true)])
        } else {
            store?.delete(kind: kind, entityId: chat.rawValue)
        }
    }
}

/// A folder's disappearing messages timer, set on its chats.
public enum IvyFolderTimers {

    /// The timers a folder can set, in seconds; 0 turns them off.
    public static let presets: [UInt32] = [0, 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60, 4 * 7 * 24 * 60 * 60]

    /// The new timer for a chat, or nil when it already has it.
    public static func token(
        forSeconds seconds: UInt32,
        current: DisappearingMessagesConfigurationRecord,
    ) -> VersionedDisappearingMessageToken? {
        let currentSeconds = current.isEnabled ? current.durationSeconds : 0
        guard currentSeconds != seconds else {
            return nil
        }
        return VersionedDisappearingMessageToken(durationSeconds: seconds, version: current.timerVersion + 1)
    }
}

extension NotificationType {

    /// Hidden chats' notifications show neither name nor content; locked
    /// chats' show the name only.
    public func ivyForChat(_ thread: TSThread) -> NotificationType {
        if IvyHiddenChats.shared.isHidden(thread: thread) {
            return .noNameNoPreview
        }
        if IvyLockedChats.shared.isLocked(thread: thread), self == .namePreview {
            return .nameNoPreview
        }
        return self
    }
}
