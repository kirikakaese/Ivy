//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A sync message to the user's own devices that carries Ivy data. The
/// payload sits in a field of `SyncMessage` that official clients don't
/// know, so they ignore the message.
@objc(IvyOutgoingDataSyncMessage)
final class IvyOutgoingDataSyncMessage: OutgoingSyncMessage {

    private let payload: Data

    init(localThread: TSContactThread, payload: IvySyncPayload, tx: DBReadTransaction) throws {
        self.payload = try payload.encoded()
        super.init(localThread: localThread, tx: tx)
    }

    override class var supportsSecureCoding: Bool { true }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(payload as NSData, forKey: "ivyPayload")
    }

    required init?(coder: NSCoder) {
        guard let payload = coder.decodeObject(of: NSData.self, forKey: "ivyPayload") as Data? else {
            return nil
        }
        self.payload = payload
        super.init(coder: coder)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(super.hash)
        hasher.combine(payload)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self, super.isEqual(object) else { return false }
        return payload == object.payload
    }

    override func syncMessageBuilder(tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {
        guard
            let decoded = IvySyncPayload.decode(payload),
            let field = try? decoded.protobufField(),
            // Parsing the bare field keeps it as an unknown field of the
            // upstream message, which writes it back unchanged.
            let unknownFields = try? SSKProtoSyncMessage(serializedData: field).unknownFields
        else {
            owsFailDebug("Couldn't build the Ivy data sync message")
            return nil
        }
        let builder = SSKProtoSyncMessage.builder()
        builder.setUnknownFields(unknownFields)
        return builder
    }

    override var contentHint: SealedSenderContentHint { .implicit }
}

/// Sends Ivy data edits to the user's other devices and applies theirs.
public final class IvyDataSync {

    private let store: IvyDataStore
    private var pendingChanges = [IvyDataChange]()
    private var isSendScheduled = false
    private let queue = DispatchQueue(label: "org.ivy.data-sync")

    /// Local edits are collected for this long and sent together.
    private static let sendDelay: TimeInterval = 2

    private static let requestedSnapshotKey = "requestedSnapshot"
    private let keyValueStore = KeyValueStore(collection: "IvyDataSync")

    init(store: IvyDataStore) {
        self.store = store
        store.onLocalChanges = { [weak self] changes in
            self?.enqueue(changes)
        }
    }

    // MARK: - Sending

    private func enqueue(_ changes: [IvyDataChange]) {
        queue.async { [self] in
            pendingChanges += changes
            guard !isSendScheduled else {
                return
            }
            isSendScheduled = true
            queue.asyncAfter(deadline: .now() + Self.sendDelay) { [self] in
                let changes = pendingChanges
                pendingChanges = []
                isSendScheduled = false
                send(IvySyncPayload.payloads(kind: .changes, changes: changes))
            }
        }
    }

    private func send(_ payloads: [IvySyncPayload]) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        databaseStorage.asyncWrite { tx in
            Self.enqueue(payloads, tx: tx)
        }
    }

    private static func enqueue(_ payloads: [IvySyncPayload], tx: DBWriteTransaction) {
        guard
            let registeredState = try? DependenciesBridge.shared.tsAccountManager.registeredState(tx: tx),
            DependenciesBridge.shared.deviceStore.fetchAll(tx: tx).count > 1
        else {
            // No other devices to tell.
            return
        }
        let localThread = TSContactThread.getOrCreateThread(
            withContactAddress: registeredState.localIdentifiers.aciAddress,
            transaction: tx,
        )
        for payload in payloads {
            do {
                let message = try IvyOutgoingDataSyncMessage(localThread: localThread, payload: payload, tx: tx)
                let prepared = PreparedOutgoingMessage.preprepared(transientMessageWithoutAttachments: message)
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: prepared, transaction: tx)
            } catch {
                owsFailDebug("Couldn't prepare the Ivy data sync message: \(error)")
            }
        }
    }

    /// Asks the user's other Ivy devices for all their Ivy data, once per
    /// device, or again when `force` is set.
    public func requestSnapshotIfNeeded(force: Bool = false) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        databaseStorage.asyncWrite { [keyValueStore] tx in
            guard force || !keyValueStore.getBool(Self.requestedSnapshotKey, defaultValue: false, transaction: tx) else {
                return
            }
            guard (try? DependenciesBridge.shared.tsAccountManager.registeredState(tx: tx)) != nil else {
                return
            }
            keyValueStore.setBool(true, key: Self.requestedSnapshotKey, transaction: tx)
            Self.enqueue([IvySyncPayload(kind: .requestSnapshot)], tx: tx)
        }
    }

    // MARK: - Receiving

    /// Handles the Ivy payload of a sync message from one of the user's own
    /// devices. Runs after the upstream transaction is committed.
    func receive(_ payload: IvySyncPayload) {
        switch payload.kind {
        case .changes, .snapshot:
            store.apply(payload.changes)
        case .requestSnapshot:
            send(IvySyncPayload.payloads(kind: .snapshot, changes: store.allChanges()))
        }
    }

    /// Called by the message receiver for every sync message from the
    /// user's own devices.
    static func handleIncomingSyncMessage(_ syncMessage: SSKProtoSyncMessage, tx: DBWriteTransaction) {
        guard
            let unknownFields = syncMessage.unknownFields,
            let payload = IvySyncPayload.fromProtobufFields(unknownFields.data)
        else {
            return
        }
        tx.addSyncCompletion {
            DispatchQueue.global(qos: .utility).async {
                IvyData.shared?.sync.receive(payload)
            }
        }
    }
}
