import Foundation
import Security

/// Database keys in the Keychain, stored the way the Swift app stores them
/// (KeychainStorage: generic password, after first unlock, this device only).
enum Keychain {
    /// The Swift app's database key.
    static let legacy = (service: "GRDBKeyChainService", account: "GRDBDatabaseCipherKeySpec")
    static let core = (service: "IvyCoreKeyChainService", account: "IvyCoreCipherKeySpec")

    private static func query(_ item: (service: String, account: String)) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: item.service,
            kSecAttrAccount: item.account,
            // The Catalyst app's items are in the data protection keychain, not the Mac's file keychain.
            kSecUseDataProtectionKeychain: true,
        ]
    }

    static func read(_ item: (service: String, account: String)) throws -> Data? {
        var query = query(item)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return result as? Data
    }

    static func add(_ data: Data, _ item: (service: String, account: String)) throws {
        var query = query(item)
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
