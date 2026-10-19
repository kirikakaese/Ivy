//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Chats the user snoozed: they leave the chat list until a chosen time,
/// then come back marked unread. Snoozes sync to all Ivy devices (kind
/// "snooze"); whichever device is running when the time comes brings the
/// chat back.
public final class IvySnoozedChats {

    public static let shared = IvySnoozedChats()

    static let kind = "snooze"

    private enum Field {
        static let until = "until"
    }

    private let lock = NSLock()
    private var cached: [IvyChatReference: Date]?
    private var wakeTimer: Timer?
    private var isStarted = false

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
        if isStarted {
            DispatchQueue.main.async { self.refresh() }
        }
    }

    private func reload() {
        var snoozes = [IvyChatReference: Date]()
        for (id, fields) in store?.entities(kind: Self.kind) ?? [:] {
            guard
                let chat = IvyChatReference(rawValue: id),
                let millis = IvyDataStore.decode(UInt64.self, from: fields[Field.until])
            else {
                continue
            }
            snoozes[chat] = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        }
        lock.lock()
        cached = snoozes
        lock.unlock()
    }

    // MARK: - Reading

    /// Every snooze with the time it ends, including ones that ended but
    /// weren't brought back yet. Safe to call from any thread.
    public var snoozes: [IvyChatReference: Date] {
        lock.lock()
        let value = cached
        lock.unlock()
        if let value {
            return value
        }
        reload()
        lock.lock()
        defer { lock.unlock() }
        return cached ?? [:]
    }

    public func snoozedUntil(_ chat: IvyChatReference, now: Date = Date()) -> Date? {
        snoozes[chat].flatMap { $0 > now ? $0 : nil }
    }

    /// Chats snoozed right now, soonest back first.
    public func activeSnoozes(now: Date = Date()) -> [(chat: IvyChatReference, until: Date)] {
        snoozes
            .filter { $0.value > now }
            .map { (chat: $0.key, until: $0.value) }
            .sorted { ($0.until, $0.chat.rawValue) < ($1.until, $1.chat.rawValue) }
    }

    /// Unique ids of the snoozed chats' threads, for the chat list.
    public func threadIds(now: Date = Date(), tx: DBReadTransaction) -> Set<String> {
        let active = activeSnoozes(now: now)
        guard !active.isEmpty else {
            return []
        }
        return Set(active.compactMap { $0.chat.thread(tx: tx)?.uniqueId })
    }

    /// Snoozes whose time has come.
    public func ended(now: Date = Date()) -> [IvyChatReference] {
        snoozes.filter { $0.value <= now }.map(\.key)
    }

    // MARK: - Changing

    public func snooze(_ chat: IvyChatReference, until date: Date) {
        store?.update(kind: Self.kind, entityId: chat.rawValue, fields: [
            Field.until: IvyDataStore.encode(UInt64(max(date.timeIntervalSince1970, 0) * 1000)),
        ])
        reload()
    }

    public func unsnooze(_ chat: IvyChatReference) {
        store?.delete(kind: Self.kind, entityId: chat.rawValue)
        reload()
    }

    // MARK: - Bringing chats back

    /// Called when the app is ready and whenever it becomes active.
    public func start() {
        AssertIsOnMainThread()
        isStarted = true
        refresh()
    }

    /// Brings back chats whose snooze ended, marked unread, and waits for
    /// the next one.
    public func refresh() {
        AssertIsOnMainThread()
        let now = Date()
        let ended = ended(now: now)
        if !ended.isEmpty {
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                for chat in ended {
                    if let thread = chat.thread(tx: tx), !thread.isMarkedUnread {
                        thread.updateWith(isMarkedUnread: true, updateStorageService: true, transaction: tx)
                    }
                }
            }
            for chat in ended {
                unsnooze(chat)
            }
        }
        wakeTimer?.invalidate()
        wakeTimer = nil
        if let next = activeSnoozes(now: now).first?.until {
            wakeTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.5, repeats: false) { [weak self] _ in
                self?.refresh()
            }
        }
    }
}
