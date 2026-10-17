//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Entry point to Ivy's own data: the store and its sync with the user's
/// other Ivy devices.
public final class IvyData {

    public let store: IvyDataStore
    public let sync: IvyDataSync

    private init(store: IvyDataStore) {
        self.store = store
        self.sync = IvyDataSync(store: store)
    }

    private static let lock = NSLock()
    private static var _shared: IvyData?

    /// The shared instance, or nil if the database can't be opened yet, for
    /// example before the device is unlocked for the first time.
    public static var shared: IvyData? {
        lock.lock()
        defer { lock.unlock() }
        if let _shared {
            return _shared
        }
        do {
            let keychainStorage = KeychainStorageImpl(isUsingProductionService: TSConstants.isUsingProductionService)
            let database = try IvyDatabase.open(keychainStorage: keychainStorage)
            let store = try IvyDataStore(database: database, clock: IvyDataClock(deviceId: localDeviceId))
            _shared = IvyData(store: store)
        } catch {
            Logger.warn("Couldn't open Ivy data: \(error)")
        }
        return _shared
    }

    /// Deletes all Ivy data on this device, when the app's data is reset.
    public static func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        _shared = nil
        IvyDatabase.delete(keychainStorage: KeychainStorageImpl(isUsingProductionService: TSConstants.isUsingProductionService))
    }

    private static func localDeviceId() -> UInt32 {
        return DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction.ifValid?.uint32Value ?? 0
    }
}
