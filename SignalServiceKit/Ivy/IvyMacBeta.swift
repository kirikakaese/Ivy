//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The Mac beta: a build signed ad hoc, for use before Ivy has a developer
/// certificate (built with `Scripts/ivy/mac-beta.sh`, compilation condition
/// `IVY_MAC_BETA`).
///
/// macOS grants an app group container and keychain sharing only to apps
/// with a certificate, so the beta keeps its data in its own folder and its
/// keys in the login keychain. It has no extensions.
public enum IvyMacBeta {

    public static var isEnabled: Bool {
#if IVY_MAC_BETA
        return true
#else
        return false
#endif
    }

    /// Where the beta keeps the keys that the regular app keeps in the
    /// keychain.
    public static let keyFile = IvyMacBetaKeyFile(directory: dataDirectory.appendingPathComponent("Keys", isDirectory: true))

    /// `~/Library/Application Support/Ivy Beta`, used in place of the app
    /// group container.
    public static var dataDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ivy Beta", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Keys of the Mac beta, one file each, readable only by the user. A Mac
/// Catalyst app needs a certificate for the keychain; FileVault encrypts
/// these files at rest.
public final class IvyMacBetaKeyFile: KeychainStorage {

    private let directory: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    public func dataValue(service: String, key: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url(service: service, key: key)) else {
            throw KeychainError.notFound
        }
        return data
    }

    public func setDataValue(_ dataValue: Data, service: String, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = url(service: service, key: key)
        try dataValue.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func removeValue(service: String, key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = url(service: service, key: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func url(service: String, key: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        func clean(_ string: String) -> String {
            String(string.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        }
        return directory.appendingPathComponent("\(clean(service))--\(clean(key))")
    }
}
