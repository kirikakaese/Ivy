//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A message the user wrote to be sent later. The schedule syncs to all
/// Ivy devices. The device that wrote it sends it; when that device isn't
/// running at the time, another one takes over a little later, so the
/// message still goes out once.
public struct IvyScheduledMessage: Equatable, Identifiable, Sendable {

    public enum State: String, Codable, Sendable {
        case pending
        case sent
    }

    public let id: String
    public let chat: IvyChatReference
    /// The message body with its mentions and styles (`MessageBody`, archived).
    public var body: Data
    /// The body as plain text, for lists.
    public var previewText: String
    public var sendAt: Date
    /// The device that wrote the message and sends it.
    public var createdBy: UInt32
    public var createdAt: Date
    public var state: State
    public var sentAt: Date?
    /// A device that took over sending, and when.
    public var claimedBy: UInt32?
    public var claimedAt: Date?

    public init(
        id: String = UUID().uuidString,
        chat: IvyChatReference,
        body: Data,
        previewText: String,
        sendAt: Date,
        createdBy: UInt32,
        createdAt: Date = Date(),
        state: State = .pending,
        sentAt: Date? = nil,
        claimedBy: UInt32? = nil,
        claimedAt: Date? = nil,
    ) {
        self.id = id
        self.chat = chat
        self.body = body
        self.previewText = previewText
        self.sendAt = sendAt
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.state = state
        self.sentAt = sentAt
        self.claimedBy = claimedBy
        self.claimedAt = claimedAt
    }

    // MARK: - Who sends

    /// How long another device waits after the send time before it takes
    /// over from the device that wrote the message.
    public static let takeoverDelay: TimeInterval = 10 * 60
    /// How long a device waits after taking over, so a takeover by another
    /// device can reach it first.
    public static let claimSettleTime: TimeInterval = 30
    /// After this long, a takeover by a device that never sent is ignored.
    public static let claimTimeout: TimeInterval = 5 * 60

    public enum Decision: Equatable, Sendable {
        /// Nothing to do: sent already.
        case none
        /// Look again at this time.
        case wait(until: Date)
        /// Take over sending, then look again after the settle time.
        case claim
        /// Send now.
        case send
    }

    /// What `device` should do with this message at `now`.
    public func decision(for device: UInt32, now: Date) -> Decision {
        guard state == .pending else {
            return .none
        }
        guard now >= sendAt else {
            return .wait(until: sendAt)
        }
        if createdBy == device {
            return .send
        }
        if let claimedBy, let claimedAt {
            if claimedBy == device {
                let settled = claimedAt.addingTimeInterval(Self.claimSettleTime)
                return now >= settled ? .send : .wait(until: settled)
            }
            let expired = claimedAt.addingTimeInterval(Self.claimTimeout)
            guard now >= expired else {
                return .wait(until: expired)
            }
        }
        let takeover = sendAt.addingTimeInterval(Self.takeoverDelay)
        return now >= takeover ? .claim : .wait(until: takeover)
    }
}

/// Scheduled messages in the Ivy data store (kind "scheduled").
public enum IvyScheduledStore {

    public static let kind = "scheduled"

    private enum Field {
        static let chat = "chat"
        static let body = "body"
        static let previewText = "preview"
        static let sendAt = "sendAt"
        static let createdBy = "createdBy"
        static let createdAt = "createdAt"
        static let state = "state"
        static let sentAt = "sentAt"
        static let claimedBy = "claimedBy"
        static let claimedAt = "claimedAt"
    }

    /// Sent messages are kept this long, then forgotten.
    public static let keepSentFor: TimeInterval = 7 * 24 * 60 * 60

    /// Soonest first.
    public static func all(store: IvyDataStore?) -> [IvyScheduledMessage] {
        guard let store else {
            return []
        }
        return store.entities(kind: kind)
            .compactMap { id, fields in message(id: id, fields: fields) }
            .sorted { ($0.sendAt, $0.id) < ($1.sendAt, $1.id) }
    }

    public static func pending(store: IvyDataStore?) -> [IvyScheduledMessage] {
        all(store: store).filter { $0.state == .pending }
    }

    public static func message(id: String, store: IvyDataStore?) -> IvyScheduledMessage? {
        store?.entity(kind: kind, id: id).flatMap { message(id: id, fields: $0) }
    }

    /// Writes the fields that differ from the stored message.
    public static func save(_ message: IvyScheduledMessage, store: IvyDataStore?) {
        let old = self.message(id: message.id, store: store)
        var fields = [String: String?]()
        func set<T: Encodable & Equatable>(_ field: String, _ value: T?, _ oldValue: T?) {
            if old == nil || value != oldValue {
                fields.updateValue(value.map { IvyDataStore.encode($0) }, forKey: field)
            }
        }
        set(Field.chat, message.chat.rawValue, old?.chat.rawValue)
        set(Field.body, message.body.base64EncodedString(), old?.body.base64EncodedString())
        set(Field.previewText, message.previewText, old?.previewText)
        set(Field.sendAt, millis(message.sendAt), old.map { millis($0.sendAt) })
        set(Field.createdBy, message.createdBy, old?.createdBy)
        set(Field.createdAt, millis(message.createdAt), old.map { millis($0.createdAt) })
        set(Field.state, message.state, old?.state)
        set(Field.sentAt, message.sentAt.map(millis), old?.sentAt.map(millis))
        set(Field.claimedBy, message.claimedBy, old?.claimedBy)
        set(Field.claimedAt, message.claimedAt.map(millis), old?.claimedAt.map(millis))
        guard !fields.isEmpty else {
            return
        }
        store?.update(kind: kind, entityId: message.id, fields: fields)
    }

    public static func delete(id: String, store: IvyDataStore?) {
        store?.delete(kind: kind, entityId: id)
    }

    /// Forgets sent messages older than `keepSentFor`.
    public static func removeOldSent(now: Date = Date(), store: IvyDataStore?) {
        for message in all(store: store) where message.state == .sent {
            if let sentAt = message.sentAt, now.timeIntervalSince(sentAt) > keepSentFor {
                delete(id: message.id, store: store)
            }
        }
    }

    private static func millis(_ date: Date) -> UInt64 {
        UInt64(max(date.timeIntervalSince1970, 0) * 1000)
    }

    private static func date(_ string: String?) -> Date? {
        IvyDataStore.decode(UInt64.self, from: string).map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    private static func message(id: String, fields: [String: String]) -> IvyScheduledMessage? {
        guard
            let chatString = IvyDataStore.decode(String.self, from: fields[Field.chat]),
            let chat = IvyChatReference(rawValue: chatString),
            let bodyString = IvyDataStore.decode(String.self, from: fields[Field.body]),
            let body = Data(base64Encoded: bodyString),
            let sendAt = date(fields[Field.sendAt])
        else {
            return nil
        }
        return IvyScheduledMessage(
            id: id,
            chat: chat,
            body: body,
            previewText: IvyDataStore.decode(String.self, from: fields[Field.previewText]) ?? "",
            sendAt: sendAt,
            createdBy: IvyDataStore.decode(UInt32.self, from: fields[Field.createdBy]) ?? 0,
            createdAt: date(fields[Field.createdAt]) ?? sendAt,
            state: IvyDataStore.decode(IvyScheduledMessage.State.self, from: fields[Field.state]) ?? .pending,
            sentAt: date(fields[Field.sentAt]),
            claimedBy: IvyDataStore.decode(UInt32.self, from: fields[Field.claimedBy]),
            claimedAt: date(fields[Field.claimedAt]),
        )
    }
}
