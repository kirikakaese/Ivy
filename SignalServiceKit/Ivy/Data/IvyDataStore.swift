//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Data that only Ivy knows about, such as reminders and folder colors. It
/// lives in its own database next to the upstream one and syncs between the
/// user's Ivy devices.
///
/// Every entity is a set of fields. Each field keeps the timestamp of its
/// last edit, so edits on different devices merge field by field with "last
/// edit wins".
public final class IvyDataStore {

    /// Posted on the main thread after Ivy data changed, locally or from
    /// another device. `userInfo["kinds"]` holds the changed kinds.
    public static let dataDidChange = Notification.Name("IvyDataDidChange")

    private let database: DatabaseWriter
    let clock: IvyDataClock

    /// Called with local edits, which then go to the user's other devices.
    var onLocalChanges: (([IvyDataChange]) -> Void)?

    public init(database: DatabaseWriter, clock: IvyDataClock) throws {
        self.database = database
        self.clock = clock
        try Self.migrator.migrate(database)
        if let latest = try database.read({ db in try Self.latestTimestamp(db) }) {
            clock.observe(latest)
        }
    }

    // MARK: - Schema

    static let tableName = "IvyDataField"

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createFields") { db in
            try db.create(table: tableName) { table in
                table.column("kind", .text).notNull()
                table.column("entityId", .text).notNull()
                table.column("field", .text).notNull()
                table.column("value", .text)
                table.column("millis", .integer).notNull()
                table.column("deviceId", .integer).notNull()
                table.primaryKey(["kind", "entityId", "field"])
            }
        }
        return migrator
    }

    // MARK: - Reading

    /// The live entities of a kind, as field → JSON value.
    public func entities(kind: String) -> [String: [String: String]] {
        let changes = fetch(sql: "SELECT * FROM \(Self.tableName) WHERE kind = ?", arguments: [kind])
        var result = [String: [String: String]]()
        for change in changes {
            if let value = change.value {
                result[change.entityId, default: [:]][change.field] = value
            }
        }
        return result.filter { $0.value[IvyDataChange.deletedField] != "true" }
    }

    public func entity(kind: String, id: String) -> [String: String]? {
        let changes = fetch(
            sql: "SELECT * FROM \(Self.tableName) WHERE kind = ? AND entityId = ?",
            arguments: [kind, id],
        )
        var fields = [String: String]()
        for change in changes {
            fields[change.field] = change.value
        }
        guard !fields.isEmpty, fields[IvyDataChange.deletedField] != "true" else {
            return nil
        }
        return fields
    }

    /// Every stored field, including deleted entities, for sync and export.
    public func allChanges() -> [IvyDataChange] {
        return fetch(sql: "SELECT * FROM \(Self.tableName)", arguments: [])
    }

    // MARK: - Writing

    /// Sets fields of an entity on this device. Pass nil to clear a field.
    @discardableResult
    public func update(kind: String, entityId: String, fields: [String: String?]) -> [IvyDataChange] {
        let timestamp = clock.next()
        let changes = fields.map { field, value in
            IvyDataChange(kind: kind, entityId: entityId, field: field, value: value, timestamp: timestamp)
        }
        let applied = apply(changes)
        if !applied.isEmpty {
            onLocalChanges?(applied)
        }
        return applied
    }

    /// Marks an entity as deleted. The deletion syncs like any other edit.
    public func delete(kind: String, entityId: String) {
        update(kind: kind, entityId: entityId, fields: [IvyDataChange.deletedField: "true"])
    }

    /// Applies changes from another device or a backup. Returns the changes
    /// that won over the stored values.
    @discardableResult
    public func apply(_ changes: [IvyDataChange]) -> [IvyDataChange] {
        guard !changes.isEmpty else {
            return []
        }
        for change in changes {
            clock.observe(change.timestamp)
        }
        let applied: [IvyDataChange]
        do {
            applied = try database.write { db in
                var applied = [IvyDataChange]()
                for change in changes {
                    let stored = try Self.fetch(
                        db,
                        sql: "SELECT * FROM \(Self.tableName) WHERE kind = ? AND entityId = ? AND field = ?",
                        arguments: [change.kind, change.entityId, change.field],
                    ).first
                    guard change.wins(over: stored) else {
                        continue
                    }
                    try db.execute(
                        sql: """
                        INSERT OR REPLACE INTO \(Self.tableName) (kind, entityId, field, value, millis, deviceId)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            change.kind,
                            change.entityId,
                            change.field,
                            change.value,
                            Int64(bitPattern: change.timestamp.millis),
                            Int64(change.timestamp.deviceId),
                        ],
                    )
                    applied.append(change)
                }
                return applied
            }
        } catch {
            owsFailDebug("Couldn't write Ivy data: \(error)")
            return []
        }
        if !applied.isEmpty {
            let kinds = Set(applied.map(\.kind))
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.dataDidChange, object: nil, userInfo: ["kinds": kinds])
            }
        }
        return applied
    }

    // MARK: - Private

    private func fetch(sql: String, arguments: StatementArguments) -> [IvyDataChange] {
        do {
            return try database.read { db in try Self.fetch(db, sql: sql, arguments: arguments) }
        } catch {
            owsFailDebug("Couldn't read Ivy data: \(error)")
            return []
        }
    }

    private static func fetch(_ db: Database, sql: String, arguments: StatementArguments) throws -> [IvyDataChange] {
        return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            let millis: Int64 = row["millis"]
            let deviceId: Int64 = row["deviceId"]
            return IvyDataChange(
                kind: row["kind"],
                entityId: row["entityId"],
                field: row["field"],
                value: row["value"],
                timestamp: IvyDataTimestamp(millis: UInt64(bitPattern: millis), deviceId: UInt32(truncatingIfNeeded: deviceId)),
            )
        }
    }

    private static func latestTimestamp(_ db: Database) throws -> IvyDataTimestamp? {
        guard let row = try Row.fetchOne(db, sql: "SELECT millis, deviceId FROM \(tableName) ORDER BY millis DESC LIMIT 1") else {
            return nil
        }
        let millis: Int64 = row["millis"]
        let deviceId: Int64 = row["deviceId"]
        return IvyDataTimestamp(millis: UInt64(bitPattern: millis), deviceId: UInt32(truncatingIfNeeded: deviceId))
    }
}

// MARK: - JSON values

extension IvyDataStore {
    public static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            owsFailDebug("Couldn't encode Ivy data value")
            return "null"
        }
        return string
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
