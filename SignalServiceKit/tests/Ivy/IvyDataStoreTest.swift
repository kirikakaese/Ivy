//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyDataStoreTest: XCTestCase {

    private var now: UInt64 = 1_000

    private func makeStore(deviceId: UInt32 = 1) throws -> IvyDataStore {
        let clock = IvyDataClock(deviceId: { deviceId }, now: { [unowned self] in now })
        return try IvyDataStore(database: DatabaseQueue(), clock: clock)
    }

    func testUpdateAndRead() throws {
        let store = try makeStore()
        store.update(kind: "folder", entityId: "a", fields: ["color": "\"green\"", "icon": "\"star\""])
        XCTAssertEqual(store.entity(kind: "folder", id: "a"), ["color": "\"green\"", "icon": "\"star\""])
        XCTAssertEqual(store.entities(kind: "folder").count, 1)
        XCTAssertNil(store.entity(kind: "folder", id: "b"))

        store.update(kind: "folder", entityId: "a", fields: ["icon": nil])
        XCTAssertEqual(store.entity(kind: "folder", id: "a"), ["color": "\"green\""])
    }

    func testLocalChangesAreReported() throws {
        let store = try makeStore()
        var reported = [IvyDataChange]()
        store.onLocalChanges = { reported += $0 }
        store.update(kind: "folder", entityId: "a", fields: ["color": "\"red\""])
        XCTAssertEqual(reported.map(\.field), ["color"])

        reported = []
        store.apply([IvyDataChange(kind: "folder", entityId: "b", field: "color", value: "\"blue\"", timestamp: .init(millis: 5_000, deviceId: 2))])
        XCTAssertTrue(reported.isEmpty)
    }

    func testLastEditWinsPerField() throws {
        let store = try makeStore()
        store.apply([
            IvyDataChange(kind: "folder", entityId: "a", field: "color", value: "\"red\"", timestamp: .init(millis: 10, deviceId: 2)),
            IvyDataChange(kind: "folder", entityId: "a", field: "icon", value: "\"star\"", timestamp: .init(millis: 30, deviceId: 2)),
        ])
        let applied = store.apply([
            IvyDataChange(kind: "folder", entityId: "a", field: "color", value: "\"blue\"", timestamp: .init(millis: 20, deviceId: 3)),
            IvyDataChange(kind: "folder", entityId: "a", field: "icon", value: "\"moon\"", timestamp: .init(millis: 20, deviceId: 3)),
        ])
        XCTAssertEqual(applied.map(\.field), ["color"])
        XCTAssertEqual(store.entity(kind: "folder", id: "a"), ["color": "\"blue\"", "icon": "\"star\""])
    }

    func testTiesAreBrokenByDevice() throws {
        let store = try makeStore()
        store.apply([IvyDataChange(kind: "k", entityId: "a", field: "f", value: "1", timestamp: .init(millis: 10, deviceId: 2))])
        store.apply([IvyDataChange(kind: "k", entityId: "a", field: "f", value: "2", timestamp: .init(millis: 10, deviceId: 1))])
        XCTAssertEqual(store.entity(kind: "k", id: "a")?["f"], "1")
        store.apply([IvyDataChange(kind: "k", entityId: "a", field: "f", value: "3", timestamp: .init(millis: 10, deviceId: 3))])
        XCTAssertEqual(store.entity(kind: "k", id: "a")?["f"], "3")
    }

    func testClockMovesPastRemoteEdits() throws {
        let store = try makeStore()
        store.apply([IvyDataChange(kind: "k", entityId: "a", field: "f", value: "1", timestamp: .init(millis: 50_000, deviceId: 2))])
        // This device's clock is behind, but its later edit still wins.
        let local = store.update(kind: "k", entityId: "a", fields: ["f": "2"])
        XCTAssertGreaterThan(local.first!.timestamp.millis, 50_000)
        XCTAssertEqual(store.entity(kind: "k", id: "a")?["f"], "2")
    }

    func testDeletion() throws {
        let store = try makeStore()
        store.update(kind: "reminder", entityId: "a", fields: ["title": "\"x\""])
        store.delete(kind: "reminder", entityId: "a")
        XCTAssertNil(store.entity(kind: "reminder", id: "a"))
        XCTAssertTrue(store.entities(kind: "reminder").isEmpty)
        XCTAssertEqual(store.allChanges().count, 2)
    }

    func testTwoDevicesConverge() throws {
        let a = try makeStore(deviceId: 1)
        let b = try makeStore(deviceId: 2)
        a.onLocalChanges = { b.apply($0) }
        b.onLocalChanges = { a.apply($0) }
        a.update(kind: "k", entityId: "x", fields: ["f": "1", "g": "1"])
        now += 5
        b.update(kind: "k", entityId: "x", fields: ["g": "2"])
        XCTAssertEqual(a.entity(kind: "k", id: "x"), b.entity(kind: "k", id: "x"))
        XCTAssertEqual(a.entity(kind: "k", id: "x"), ["f": "1", "g": "2"])
    }

    func testJSONHelpers() {
        XCTAssertEqual(IvyDataStore.encode(["b": 1, "a": 2]), "{\"a\":2,\"b\":1}")
        XCTAssertEqual(IvyDataStore.decode([String: Int].self, from: "{\"a\":2}"), ["a": 2])
        XCTAssertNil(IvyDataStore.decode(Int.self, from: nil))
    }
}

final class IvyDataBackupTest: XCTestCase {

    private let changes = [
        IvyDataChange(kind: "folder", entityId: "a", field: "color", value: "\"green\"", timestamp: .init(millis: 10, deviceId: 1)),
        IvyDataChange(kind: "reminder", entityId: "b", field: "dueAt", value: nil, timestamp: .init(millis: 11, deviceId: 2)),
    ]

    func testRoundTrip() throws {
        let file = try IvyDataBackup.export(changes, passphrase: "correct horse", iterations: 1_000)
        XCTAssertEqual(try IvyDataBackup.import(file, passphrase: "correct horse"), changes)
    }

    func testWrongPassphrase() throws {
        let file = try IvyDataBackup.export(changes, passphrase: "correct horse", iterations: 1_000)
        XCTAssertThrowsError(try IvyDataBackup.import(file, passphrase: "battery staple")) { error in
            XCTAssertEqual(error as? IvyDataBackup.Error, .wrongPassphrase)
        }
    }

    func testOtherFiles() {
        XCTAssertThrowsError(try IvyDataBackup.import(Data("hello".utf8), passphrase: "x")) { error in
            XCTAssertEqual(error as? IvyDataBackup.Error, .notAnIvyDataFile)
        }
    }

    func testFilesDiffer() throws {
        let one = try IvyDataBackup.export(changes, passphrase: "p", iterations: 1_000)
        let two = try IvyDataBackup.export(changes, passphrase: "p", iterations: 1_000)
        XCTAssertNotEqual(one, two)
    }
}

final class IvySyncPayloadTest: XCTestCase {

    private func change(_ index: Int, size: Int = 10) -> IvyDataChange {
        IvyDataChange(
            kind: "k",
            entityId: "\(index)",
            field: "f",
            value: String(repeating: "x", count: size),
            timestamp: .init(millis: UInt64(index), deviceId: 1),
        )
    }

    func testProtobufFieldRoundTrip() throws {
        let payload = IvySyncPayload(kind: .changes, changes: [change(1)])
        // Another unknown field before ours: field 99, varint 1.
        let fields = Data([0x98, 0x06, 0x01]) + (try payload.protobufField())
        XCTAssertEqual(IvySyncPayload.fromProtobufFields(fields), payload)
        XCTAssertNil(IvySyncPayload.fromProtobufFields(Data([0x98, 0x06, 0x01])))
        XCTAssertNil(IvySyncPayload.fromProtobufFields(Data()))
    }

    func testNewerVersionsAreIgnored() throws {
        var payload = IvySyncPayload(kind: .requestSnapshot)
        payload.version = IvySyncPayload.currentVersion + 1
        XCTAssertNil(IvySyncPayload.decode(try payload.encoded()))
    }

    func testLargeSnapshotsAreSplit() throws {
        let changes = (0..<40).map { change($0, size: 4_000) }
        let payloads = IvySyncPayload.payloads(kind: .snapshot, changes: changes)
        XCTAssertGreaterThan(payloads.count, 1)
        XCTAssertEqual(payloads.flatMap(\.changes), changes)
        for payload in payloads {
            XCTAssertLessThan(try payload.encoded().count, IvySyncPayload.maxEncodedSize + 8_000)
        }
        XCTAssertEqual(IvySyncPayload.payloads(kind: .requestSnapshot, changes: []).count, 1)
    }
}
