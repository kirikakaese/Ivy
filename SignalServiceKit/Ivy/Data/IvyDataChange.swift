//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// When a field of Ivy data was last edited, and on which device. Later
/// edits win; the device id breaks ties between edits in the same
/// millisecond.
public struct IvyDataTimestamp: Codable, Comparable, Hashable, Sendable {
    public let millis: UInt64
    public let deviceId: UInt32

    public init(millis: UInt64, deviceId: UInt32) {
        self.millis = millis
        self.deviceId = deviceId
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return (lhs.millis, lhs.deviceId) < (rhs.millis, rhs.deviceId)
    }
}

/// One edited field of one Ivy data entity, such as the color of a folder or
/// the due date of a reminder. Every change carries its own timestamp, so
/// conflicts are resolved per field with "last edit wins".
public struct IvyDataChange: Codable, Equatable, Hashable, Sendable {
    /// The kind of entity, such as "folder" or "reminder".
    public let kind: String
    public let entityId: String
    public let field: String
    /// The value as JSON, or nil when the field was cleared.
    public let value: String?
    public let timestamp: IvyDataTimestamp

    public init(kind: String, entityId: String, field: String, value: String?, timestamp: IvyDataTimestamp) {
        self.kind = kind
        self.entityId = entityId
        self.field = field
        self.value = value
        self.timestamp = timestamp
    }

    /// The field that marks an entity as deleted.
    public static let deletedField = "deleted"

    public struct Key: Hashable, Sendable {
        public let kind: String
        public let entityId: String
        public let field: String
    }

    public var key: Key { Key(kind: kind, entityId: entityId, field: field) }

    /// Whether this change wins over the stored one.
    public func wins(over stored: IvyDataChange?) -> Bool {
        guard let stored else {
            return true
        }
        return timestamp > stored.timestamp
    }
}

/// A clock for Ivy data timestamps that never goes backwards, even when the
/// device clocks of the user's devices differ.
public final class IvyDataClock {
    private let deviceId: () -> UInt32
    private let now: () -> UInt64
    private var lastMillis: UInt64 = 0
    private let lock = NSLock()

    public init(deviceId: @escaping () -> UInt32, now: @escaping () -> UInt64 = { Date.ows_millisecondTimestamp() }) {
        self.deviceId = deviceId
        self.now = now
    }

    public func next() -> IvyDataTimestamp {
        lock.lock()
        defer { lock.unlock() }
        lastMillis = max(now(), lastMillis + 1)
        return IvyDataTimestamp(millis: lastMillis, deviceId: deviceId())
    }

    /// Moves the clock past a timestamp received from another device.
    public func observe(_ timestamp: IvyDataTimestamp) {
        lock.lock()
        defer { lock.unlock() }
        lastMillis = max(lastMillis, timestamp.millis)
    }
}
