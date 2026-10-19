//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Chats the user hid from the chat list. They show again only after the
/// user unlocks them with Face ID, Touch ID or the device passcode, until
/// Ivy goes to the background or locks. Their notifications say only "New
/// message", without name or content. Hidden chats sync to all Ivy devices
/// (kind "hiddenChat").
public final class IvyHiddenChats {

    public static let shared = IvyHiddenChats()

    /// Posted on the main thread when chats were hidden, shown or revealed.
    public static let hiddenChatsDidChange = Notification.Name("IvyHiddenChatsDidChange")

    static let kind = "hiddenChat"

    private enum Field {
        static let hiddenAt = "hiddenAt"
    }

    private let lock = NSLock()
    private var hidden: Set<IvyChatReference>?
    private var _isRevealed = false

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
        hidden = chats
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.hiddenChatsDidChange, object: nil)
        }
    }

    /// The hidden chats. Safe to call from any thread.
    public var chats: Set<IvyChatReference> {
        lock.lock()
        let cached = hidden
        lock.unlock()
        if let cached {
            return cached
        }
        reload()
        lock.lock()
        defer { lock.unlock() }
        return hidden ?? []
    }

    public var isEmpty: Bool { chats.isEmpty }

    public func isHidden(_ chat: IvyChatReference) -> Bool {
        chats.contains(chat)
    }

    public func isHidden(thread: TSThread) -> Bool {
        guard !isEmpty, let chat = IvyChatReference(thread: thread) else {
            return false
        }
        return isHidden(chat)
    }

    /// Unique ids of the hidden chats' threads, for the chat list.
    public func threadIds(tx: DBReadTransaction) -> Set<String> {
        Set(chats.compactMap { $0.thread(tx: tx)?.uniqueId })
    }

    // MARK: - Hiding

    public func hide(_ chat: IvyChatReference, now: Date = Date()) {
        store?.update(kind: Self.kind, entityId: chat.rawValue, fields: [
            Field.hiddenAt: IvyDataStore.encode(UInt64(now.timeIntervalSince1970 * 1000)),
        ])
        reload()
    }

    public func unhide(_ chat: IvyChatReference) {
        store?.delete(kind: Self.kind, entityId: chat.rawValue)
        reload()
    }

    // MARK: - Revealing

    /// Whether hidden chats show in the chat list right now.
    public var isRevealed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRevealed
    }

    /// Call only after the user authenticated.
    public func setRevealed(_ revealed: Bool) {
        lock.lock()
        let changed = _isRevealed != revealed
        _isRevealed = revealed
        lock.unlock()
        if changed {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.hiddenChatsDidChange, object: nil)
            }
        }
    }
}

extension NotificationType {

    /// A hidden chat's notifications show neither name nor content.
    public func ivyForChat(_ thread: TSThread) -> NotificationType {
        IvyHiddenChats.shared.isHidden(thread: thread) ? .noNameNoPreview : self
    }
}
