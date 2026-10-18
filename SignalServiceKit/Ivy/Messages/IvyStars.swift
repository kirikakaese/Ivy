//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A starred message: a bookmark with a short quote, so the list of starred
/// messages can show it without opening the chat.
public struct IvyStar: Equatable, Identifiable, Sendable {

    public let message: IvyMessageReference
    public var quote: String
    public var starredAt: Date

    /// The same message gets the same id on every device, so starring it
    /// on two devices keeps one star.
    public var id: String { Self.id(for: message) }

    public init(message: IvyMessageReference, quote: String, starredAt: Date = Date()) {
        self.message = message
        self.quote = quote
        self.starredAt = starredAt
    }

    public static func id(for message: IvyMessageReference) -> String {
        "\(message.chat.rawValue)|\(message.timestamp)|\(message.authorAci ?? "")"
    }
}

/// Stars in the Ivy data store (kind "star").
public enum IvyStarStore {

    static let kind = "star"

    private enum Field {
        static let message = "message"
        static let quote = "quote"
        static let starredAt = "starredAt"
    }

    /// Newest first.
    public static func all(store: IvyDataStore?) -> [IvyStar] {
        guard let store else {
            return []
        }
        return store.entities(kind: kind)
            .compactMap { _, fields in star(fields: fields) }
            .sorted { $0.starredAt > $1.starredAt }
    }

    public static func save(_ star: IvyStar, store: IvyDataStore?) {
        store?.update(kind: kind, entityId: star.id, fields: [
            Field.message: IvyDataStore.encode(star.message),
            Field.quote: star.quote,
            Field.starredAt: IvyDataStore.encode(UInt64(star.starredAt.timeIntervalSince1970 * 1000)),
        ])
    }

    public static func delete(message: IvyMessageReference, store: IvyDataStore?) {
        store?.delete(kind: kind, entityId: IvyStar.id(for: message))
    }

    private static func star(fields: [String: String]) -> IvyStar? {
        guard let message = IvyDataStore.decode(IvyMessageReference.self, from: fields[Field.message]) else {
            return nil
        }
        let millis = IvyDataStore.decode(UInt64.self, from: fields[Field.starredAt]) ?? 0
        return IvyStar(
            message: message,
            quote: fields[Field.quote] ?? "",
            starredAt: Date(timeIntervalSince1970: TimeInterval(millis) / 1000),
        )
    }
}

/// A private note for a chat, in the Ivy data store (kind "chatNote"). Only
/// the user's own devices see it.
public enum IvyChatNoteStore {

    static let kind = "chatNote"

    private enum Field {
        static let text = "text"
    }

    /// The longest note kept.
    public static let maxLength = 10_000

    public static func note(for chat: IvyChatReference, store: IvyDataStore?) -> String {
        store?.entity(kind: kind, id: chat.rawValue)?[Field.text] ?? ""
    }

    /// Saves the note; an empty note is removed.
    public static func save(_ text: String, for chat: IvyChatReference, store: IvyDataStore?) {
        let text = String(text.prefix(maxLength))
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            if store?.entity(kind: kind, id: chat.rawValue) != nil {
                store?.delete(kind: kind, entityId: chat.rawValue)
            }
            return
        }
        guard text != note(for: chat, store: store) else {
            return
        }
        store?.update(kind: kind, entityId: chat.rawValue, fields: [Field.text: text])
    }
}

/// Keeps stars working on this device: the star on starred messages, and
/// removing the star when its message goes away.
public final class IvyStarManager {

    public static let shared = IvyStarManager()

    /// Posted on the main thread when stars changed.
    public static let starsDidChange = Notification.Name("IvyStarsDidChange")

    private var isStarted = false
    private var store: IvyDataStore? { IvyData.shared?.store }

    private let lock = NSLock()
    private var starredMessages = Set<IvyMessageReference>()

    /// Called when the app is ready and whenever it becomes active.
    public func start() {
        AssertIsOnMainThread()
        if !isStarted {
            isStarted = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(dataDidChange(_:)),
                name: IvyDataStore.dataDidChange,
                object: nil,
            )
        }
        refresh()
    }

    @objc
    private func dataDidChange(_ notification: Notification) {
        guard let kinds = notification.userInfo?["kinds"] as? Set<String>, kinds.contains(IvyStarStore.kind) else {
            return
        }
        refresh()
    }

    public func refresh() {
        AssertIsOnMainThread()
        let messages = Set(IvyStarStore.all(store: store).map(\.message))
        lock.lock()
        let changed = starredMessages.symmetricDifference(messages)
        starredMessages = messages
        lock.unlock()
        redraw(changed)
        NotificationCenter.default.post(name: Self.starsDidChange, object: nil)
    }

    public func allStars() -> [IvyStar] {
        IvyStarStore.all(store: store)
    }

    public func star(_ message: TSMessage, thread: TSThread) {
        guard let reference = IvyMessageReference(message: message, thread: thread) else {
            return
        }
        IvyStarStore.save(IvyStar(message: reference, quote: IvyTask.quote(fromMessageText: message.body ?? "")), store: store)
        refresh()
    }

    public func unstar(_ message: IvyMessageReference) {
        IvyStarStore.delete(message: message, store: store)
        refresh()
    }

    /// Whether a message is starred. Safe to call from any thread.
    public func isStarred(message: TSMessage, thread: TSThread) -> Bool {
        lock.lock()
        let isEmpty = starredMessages.isEmpty
        lock.unlock()
        guard !isEmpty, let reference = IvyMessageReference(message: message, thread: thread) else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        return starredMessages.contains(reference)
    }

    func linksToMessage(timestamp: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return starredMessages.contains { $0.timestamp == timestamp }
    }

    func removeStars(_ messages: Set<IvyMessageReference>) {
        for message in messages {
            IvyStarStore.delete(message: message, store: store)
        }
        refresh()
    }

    /// Redraws the messages whose star changed.
    private func redraw(_ messages: Set<IvyMessageReference>) {
        guard !messages.isEmpty else {
            return
        }
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        databaseStorage.asyncWrite { tx in
            for message in messages {
                if let interaction = message.message(tx: tx) {
                    databaseStorage.touch(interaction: interaction, shouldReindex: false, tx: tx)
                }
            }
        }
    }
}
