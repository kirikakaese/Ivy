//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyMacBetaKeyFileTest: XCTestCase {

    func testStoresReadsAndRemovesKeys() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyFile = IvyMacBetaKeyFile(directory: directory)

        XCTAssertThrowsError(try keyFile.dataValue(service: "GRDBKeyChainService", key: "Key")) { error in
            guard case KeychainError.notFound = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }

        let key = Data(repeating: 7, count: 48)
        try keyFile.setDataValue(key, service: "GRDBKeyChainService", key: "Key")
        XCTAssertEqual(try keyFile.dataValue(service: "GRDBKeyChainService", key: "Key"), key)
        XCTAssertThrowsError(try keyFile.dataValue(service: "Other/Service", key: "Key"))

        let replacement = Data(repeating: 9, count: 48)
        try keyFile.setDataValue(replacement, service: "GRDBKeyChainService", key: "Key")
        XCTAssertEqual(try keyFile.dataValue(service: "GRDBKeyChainService", key: "Key"), replacement)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(files[0]).path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)

        try keyFile.removeValue(service: "GRDBKeyChainService", key: "Key")
        try keyFile.removeValue(service: "GRDBKeyChainService", key: "Key")
        XCTAssertThrowsError(try keyFile.dataValue(service: "GRDBKeyChainService", key: "Key"))
    }
}
