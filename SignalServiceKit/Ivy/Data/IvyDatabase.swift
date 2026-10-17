//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Opens Ivy's own database, `ivy-db/ivy.sqlite` in the shared container
/// next to the upstream database. It is encrypted with SQLCipher like the
/// upstream database, with its own key in the keychain.
enum IvyDatabase {

    private static let keyServiceName = "IvyDataKeyChainService"
    private static let keyName = "IvyDataCipherKeySpec"
    /// A 256-bit key and a 128-bit salt, as for the upstream database.
    private static let keySpecLength = 48

    /// Not "grdb…": upstream removes directories with that prefix that it
    /// doesn't use.
    static let directoryName = "ivy-db"

    static var databaseURL: URL {
        return URL(fileURLWithPath: CurrentAppContext().appDatabaseBaseDirectoryPath())
            .appendingPathComponent(directoryName)
            .appendingPathComponent("ivy.sqlite")
    }

    static func open(keychainStorage: any KeychainStorage) throws -> DatabasePool {
        let url = databaseURL
        OWSFileSystem.ensureDirectoryExists(url.deletingLastPathComponent().path)
        let keySpec = try fetchOrCreateKeySpec(keychainStorage: keychainStorage)
        let pool = try openPool(url: url, configuration: configuration(keySpec: keySpec))
        OWSFileSystem.protectFileOrFolder(atPath: url.deletingLastPathComponent().path)
        OWSFileSystem.protectFileOrFolder(atPath: url.path)
        return pool
    }

    /// Removes the database and its key, when the app's data is reset.
    static func delete(keychainStorage: any KeychainStorage) {
        try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
        try? keychainStorage.removeValue(service: keyServiceName, key: keyName)
    }

    // MARK: - Private

    private static func fetchOrCreateKeySpec(keychainStorage: any KeychainStorage) throws -> String {
        let data: Data
        do {
            data = try keychainStorage.dataValue(service: keyServiceName, key: keyName)
        } catch KeychainError.notFound {
            // A key without its database is useless, and a database without
            // its key is unreadable: start both from scratch.
            try? FileManager.default.removeItem(at: databaseURL)
            data = Randomness.generateRandomBytes(UInt(keySpecLength))
            try keychainStorage.setDataValue(data, service: keyServiceName, key: keyName)
        }
        guard data.count == keySpecLength else {
            throw OWSAssertionError("Unexpected Ivy database key length")
        }
        return "x'\(data.hexadecimalString)'"
    }

    private static func configuration(keySpec: String) -> Configuration {
        var configuration = Configuration()
        configuration.label = "Ivy Data"
        configuration.maximumReaderCount = CurrentAppContext().isMainApp ? 4 : 2
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            // The same settings as the upstream database.
            try db.execute(sql: "PRAGMA key = \"\(keySpec)\"")
            try db.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
            try db.execute(sql: "PRAGMA checkpoint_fullfsync = ON")
        }
        configuration.defaultTransactionKind = .immediate
        return configuration
    }

    // See https://github.com/groue/GRDB.swift/blob/master/Documentation/SharingADatabase.md
    private static func openPool(url: URL, configuration: Configuration) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var result: Result<DatabasePool, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { url in
            result = Result { try DatabasePool(path: url.path, configuration: configuration) }
        }
        if let coordinatorError {
            throw coordinatorError
        }
        guard let result else {
            throw OWSAssertionError("The Ivy database was not opened")
        }
        return try result.get()
    }
}
