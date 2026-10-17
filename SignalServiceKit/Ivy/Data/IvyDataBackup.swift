//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import CryptoKit
import Foundation

/// Encrypted export and import of all Ivy data.
///
/// File layout: the magic bytes "IVYDATA1", a 16-byte salt, the PBKDF2
/// iteration count (4 bytes, big endian) and an AES-256-GCM box (nonce,
/// ciphertext, tag) with the JSON list of all Ivy data fields. The key is
/// derived from the passphrase with PBKDF2-HMAC-SHA256.
public enum IvyDataBackup {

    public static let fileExtension = "ivydata"

    public enum Error: Swift.Error, Equatable {
        case notAnIvyDataFile
        case wrongPassphrase
        case unreadable
    }

    private static let magic = Data("IVYDATA1".utf8)
    static let defaultIterations: UInt32 = 310_000

    public static func export(_ changes: [IvyDataChange], passphrase: String, iterations: UInt32 = defaultIterations) throws -> Data {
        let payload = try JSONEncoder().encode(changes)
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        guard let sealed = try AES.GCM.seal(payload, using: key).combined else {
            throw Error.unreadable
        }
        var iterationBytes = iterations.bigEndian
        return magic + salt + Data(bytes: &iterationBytes, count: 4) + sealed
    }

    public static func `import`(_ data: Data, passphrase: String) throws -> [IvyDataChange] {
        let headerLength = magic.count + 16 + 4
        guard data.count > headerLength, data.prefix(magic.count) == magic else {
            throw Error.notAnIvyDataFile
        }
        let bytes = Data(data)
        let salt = bytes.subdata(in: magic.count..<(magic.count + 16))
        let iterations = bytes.subdata(in: (magic.count + 16)..<headerLength).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard iterations > 0, iterations <= 10_000_000 else {
            throw Error.notAnIvyDataFile
        }
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let payload: Data
        do {
            payload = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes.subdata(in: headerLength..<bytes.count)), using: key)
        } catch {
            throw Error.wrongPassphrase
        }
        do {
            return try JSONDecoder().decode([IvyDataChange].self, from: payload)
        } catch {
            throw Error.unreadable
        }
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password.map { CChar(bitPattern: $0) },
                password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                iterations,
                &derived,
                derived.count,
            )
        }
        guard status == kCCSuccess else {
            throw Error.unreadable
        }
        return SymmetricKey(data: derived)
    }
}
