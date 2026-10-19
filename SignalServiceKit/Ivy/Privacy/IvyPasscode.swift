//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import CommonCrypto
import Foundation

/// Ivy's own passcode for Screen Lock. When it is set, unlocking Ivy asks
/// for it instead of the device's passcode; Face ID or Touch ID can stay as
/// a shortcut. Only a salted PBKDF2 hash is stored, on this device only.
/// Wrong attempts make the next try wait longer.
///
/// A second, duress passcode can be set too: entering it opens a decoy mode
/// instead of Ivy (see `IvyDecoy`).
public enum IvyPasscode {

    private static let store = KeyValueStore(collection: "IvyPasscode")

    private enum Key {
        static let salt = "salt"
        static let hash = "hash"
        static let iterations = "iterations"
        static let allowsBiometrics = "allowsBiometrics"
        static let failedAttempts = "failedAttempts"
        static let blockedUntil = "blockedUntil"
        static let duressSalt = "duressSalt"
        static let duressHash = "duressHash"
    }

    /// The shortest passcode accepted.
    public static let minimumLength = 4
    static let defaultIterations: UInt32 = 200_000
    /// Free attempts before Ivy makes the user wait.
    static let freeAttempts = 5

    public enum Result: Equatable {
        case correct
        case wrong
        /// The duress passcode: show the decoy mode.
        case duress
        /// Too many wrong attempts: try again after this date.
        case blocked(until: Date)
    }

    // MARK: - Reading

    public static func isSet(tx: DBReadTransaction) -> Bool {
        store.getData(Key.hash, transaction: tx) != nil
    }

    public static func isDuressSet(tx: DBReadTransaction) -> Bool {
        store.getData(Key.duressHash, transaction: tx) != nil
    }

    /// Whether Face ID or Touch ID may unlock instead of the passcode.
    public static func allowsBiometrics(tx: DBReadTransaction) -> Bool {
        store.getBool(Key.allowsBiometrics, defaultValue: true, transaction: tx)
    }

    public static func blockedUntil(now: Date = Date(), tx: DBReadTransaction) -> Date? {
        guard let date = store.getDate(Key.blockedUntil, transaction: tx), date > now else {
            return nil
        }
        return date
    }

    // MARK: - Changing

    /// Sets the passcode. False when it is the duress passcode.
    @discardableResult
    public static func set(_ passcode: String, tx: DBWriteTransaction) -> Bool {
        guard !matches(passcode, salt: Key.duressSalt, hash: Key.duressHash, tx: tx) else {
            return false
        }
        let salt = newSalt()
        store.setData(salt, key: Key.salt, transaction: tx)
        store.setUInt32(defaultIterations, key: Key.iterations, transaction: tx)
        store.setData(hash(passcode, salt: salt, iterations: defaultIterations), key: Key.hash, transaction: tx)
        resetAttempts(tx: tx)
        return true
    }

    /// Removes the passcode, and the duress passcode with it.
    public static func remove(tx: DBWriteTransaction) {
        store.removeValues(forKeys: [Key.salt, Key.hash, Key.iterations, Key.failedAttempts, Key.blockedUntil], transaction: tx)
        removeDuress(tx: tx)
    }

    /// Sets the duress passcode. False when there is no passcode yet, or
    /// when it is the passcode itself.
    @discardableResult
    public static func setDuress(_ passcode: String, tx: DBWriteTransaction) -> Bool {
        guard isSet(tx: tx), !matches(passcode, salt: Key.salt, hash: Key.hash, tx: tx) else {
            return false
        }
        let salt = newSalt()
        store.setData(salt, key: Key.duressSalt, transaction: tx)
        store.setData(hash(passcode, salt: salt, iterations: iterations(tx: tx)), key: Key.duressHash, transaction: tx)
        return true
    }

    public static func removeDuress(tx: DBWriteTransaction) {
        store.removeValues(forKeys: [Key.duressSalt, Key.duressHash], transaction: tx)
    }

    public static func setAllowsBiometrics(_ value: Bool, tx: DBWriteTransaction) {
        store.setBool(value, key: Key.allowsBiometrics, transaction: tx)
    }

    // MARK: - Checking

    /// Checks a passcode and counts wrong attempts.
    public static func verify(_ passcode: String, now: Date = Date(), tx: DBWriteTransaction) -> Result {
        if let blockedUntil = blockedUntil(now: now, tx: tx) {
            return .blocked(until: blockedUntil)
        }
        guard isSet(tx: tx) else {
            return .wrong
        }
        if matches(passcode, salt: Key.salt, hash: Key.hash, tx: tx) {
            resetAttempts(tx: tx)
            return .correct
        }
        if matches(passcode, salt: Key.duressSalt, hash: Key.duressHash, tx: tx) {
            resetAttempts(tx: tx)
            return .duress
        }
        let failed = store.getInt(Key.failedAttempts, defaultValue: 0, transaction: tx) + 1
        store.setInt(failed, key: Key.failedAttempts, transaction: tx)
        if let delay = delay(afterFailedAttempts: failed) {
            let until = now.addingTimeInterval(delay)
            store.setDate(until, key: Key.blockedUntil, transaction: tx)
            return .blocked(until: until)
        }
        return .wrong
    }

    /// After the free attempts: 30 seconds, then twice as long each time,
    /// at most an hour.
    static func delay(afterFailedAttempts failed: Int) -> TimeInterval? {
        guard failed >= freeAttempts else {
            return nil
        }
        let doublings = min(failed - freeAttempts, 7)
        return min(30 * pow(2, Double(doublings)), 60 * 60)
    }

    private static func resetAttempts(tx: DBWriteTransaction) {
        store.removeValues(forKeys: [Key.failedAttempts, Key.blockedUntil], transaction: tx)
    }

    // MARK: - Hashing

    private static func newSalt() -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return salt
    }

    private static func iterations(tx: DBReadTransaction) -> UInt32 {
        store.getUInt32(Key.iterations, defaultValue: defaultIterations, transaction: tx)
    }

    private static func matches(_ passcode: String, salt saltKey: String, hash hashKey: String, tx: DBReadTransaction) -> Bool {
        guard
            let salt = store.getData(saltKey, transaction: tx),
            let expected = store.getData(hashKey, transaction: tx)
        else {
            return false
        }
        return constantTimeEquals(hash(passcode, salt: salt, iterations: iterations(tx: tx)), expected)
    }

    static func hash(_ passcode: String, salt: Data, iterations: UInt32) -> Data {
        let password = Array(passcode.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        _ = salt.withUnsafeBytes { saltBytes in
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
        return Data(derived)
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
