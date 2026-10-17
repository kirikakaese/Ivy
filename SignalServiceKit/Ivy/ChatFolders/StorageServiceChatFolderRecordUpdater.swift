//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SwiftProtobuf

/// Syncs chat folders as storage service `ChatFolderRecord`s, the format
/// that official clients with chat folders use.
final class StorageServiceChatFolderRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = IvyStorageProtos_ChatFolderRecord

    static let keyType = StorageServiceProtoManifestRecordKeyType.UNRECOGNIZED(IvyStorageProtos_KeyType.chatFolder)

    let chatFolderManager: ChatFolderManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientFetcher: RecipientFetcher
    private let threadStore: ThreadStore

    init(
        chatFolderManager: ChatFolderManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        threadStore: ThreadStore,
    ) {
        self.chatFolderManager = chatFolderManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.threadStore = threadStore
    }

    func unknownFields(for record: RecordType) -> UnknownStorage? {
        return record.unknownFields.data.isEmpty ? nil : record.unknownFields
    }

    func buildStorageItem(for record: RecordType) -> StorageService.StorageItem {
        var storageRecord = IvyStorageProtos_StorageRecord()
        storageRecord.chatFolder = record
        let upstreamRecord = failIfThrows {
            // The upstream message keeps field 8 as an unknown field and
            // writes it back unchanged when the item is encrypted.
            try StorageServiceProtoStorageRecord(serializedData: storageRecord.serializedData())
        }
        return StorageService.StorageItem(identifier: .generate(type: Self.keyType), record: upstreamRecord)
    }

    func buildRecord(for folderId: Data, unknownFields: UnknownStorage?, transaction tx: DBReadTransaction) -> RecordType? {
        guard let folder = chatFolderManager.folder(id: folderId, tx: tx) else {
            return nil
        }
        var record = RecordType()
        record.identifier = folder.id
        record.folderType = folder.kind == .allChats ? .all : .custom
        if let deletedAtTimestampMs = folder.deletedAtTimestampMs {
            record.deletedAtTimestampMs = deletedAtTimestampMs
            // Official clients send deleted folders with position -1.
            record.position = UInt32.max
        } else {
            record.name = folder.name
            record.position = folder.position
            record.showOnlyUnread = folder.showOnlyUnread
            record.showMutedChats = folder.showMutedChats
            record.includeAllIndividualChats = folder.includeAllIndividualChats
            record.includeAllGroupChats = folder.includeAllGroupChats
            record.includedRecipients = recipients(
                threadIds: folder.includedThreadIds,
                unresolved: folder.unresolvedIncludedRecipients,
                tx: tx,
            )
            record.excludedRecipients = recipients(
                threadIds: folder.excludedThreadIds,
                unresolved: folder.unresolvedExcludedRecipients,
                tx: tx,
            )
        }
        if let unknownFields {
            record.unknownFields = unknownFields
        }
        return record
    }

    func mergeRecord(_ record: RecordType, transaction tx: DBWriteTransaction) -> StorageServiceMergeResult<Data> {
        guard record.identifier.count == 16 else {
            owsFailDebug("Chat folder record without a valid identifier")
            return .invalid
        }
        let existing = chatFolderManager.folder(id: record.identifier, tx: tx)
        var folder = existing ?? ChatFolder(id: record.identifier, name: record.name)
        folder.kind = record.folderType == .all ? .allChats : .custom
        if record.deletedAtTimestampMs > 0 {
            folder.deletedAtTimestampMs = record.deletedAtTimestampMs
            folder.includedThreadIds = []
            folder.excludedThreadIds = []
            folder.unresolvedIncludedRecipients = []
            folder.unresolvedExcludedRecipients = []
        } else {
            folder.deletedAtTimestampMs = nil
            folder.name = record.name
            folder.position = record.position
            folder.showOnlyUnread = record.showOnlyUnread
            folder.showMutedChats = record.showMutedChats
            folder.includeAllIndividualChats = record.includeAllIndividualChats
            folder.includeAllGroupChats = record.includeAllGroupChats
            (folder.includedThreadIds, folder.unresolvedIncludedRecipients) = threadIds(record.includedRecipients, tx: tx)
            (folder.excludedThreadIds, folder.unresolvedExcludedRecipients) = threadIds(record.excludedRecipients, tx: tx)
        }
        chatFolderManager.applyRemote(folder, tx: tx)
        if folder.kind == .allChats, !folder.isDeleted {
            chatFolderManager.deleteOtherAllChatsFolders(keeping: folder.id, tx: tx)
        }
        return .merged(needsUpdate: false, record.identifier)
    }

    // MARK: - Recipients

    private func recipients(threadIds: [String], unresolved: [Data], tx: DBReadTransaction) -> [IvyStorageProtos_Recipient] {
        var result = [IvyStorageProtos_Recipient]()
        for threadId in threadIds {
            guard let thread = threadStore.fetchThread(uniqueId: threadId, tx: tx) else {
                continue
            }
            var recipient = IvyStorageProtos_Recipient()
            if let groupThread = thread as? TSGroupThread {
                if let groupModel = groupThread.groupModel as? TSGroupModelV2, let masterKey = try? groupModel.masterKey() {
                    recipient.identifier = .groupMasterKey(masterKey.serialize())
                } else {
                    recipient.identifier = .legacyGroupID(groupThread.groupId)
                }
            } else if let contactThread = thread as? TSContactThread {
                let address = contactThread.contactAddress
                var contact = IvyStorageProtos_Recipient.Contact()
                if let aci = address.aci {
                    contact.serviceIDBinary = aci.serviceIdBinary
                } else if let phoneNumber = address.phoneNumber {
                    contact.e164 = phoneNumber
                } else if let serviceId = address.serviceId {
                    contact.serviceIDBinary = serviceId.serviceIdBinary
                } else {
                    continue
                }
                recipient.identifier = .contact(contact)
            } else {
                continue
            }
            result.append(recipient)
        }
        for data in unresolved {
            if let recipient = try? IvyStorageProtos_Recipient(serializedBytes: data) {
                result.append(recipient)
            }
        }
        return result
    }

    /// The local chats for the records' recipients, and the recipients for
    /// which there is no chat on this device.
    private func threadIds(_ recipients: [IvyStorageProtos_Recipient], tx: DBWriteTransaction) -> ([String], [Data]) {
        var threadIds = [String]()
        var unresolved = [Data]()
        for recipient in recipients {
            if let threadId = threadId(for: recipient, tx: tx) {
                if !threadIds.contains(threadId) {
                    threadIds.append(threadId)
                }
            } else if let data = try? recipient.serializedData() {
                unresolved.append(data)
            }
        }
        return (threadIds, unresolved)
    }

    private func threadId(for recipient: IvyStorageProtos_Recipient, tx: DBWriteTransaction) -> String? {
        switch recipient.identifier {
        case .contact(let contact)?:
            let serviceId = ServiceId.parseFrom(
                serviceIdBinary: contact.serviceIDBinary.nilIfEmpty,
                serviceIdString: contact.serviceID.nilIfEmpty,
            )
            let signalRecipient: SignalRecipient
            if let aci = serviceId as? Aci {
                signalRecipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
            } else if let phoneNumber = E164(contact.e164) {
                signalRecipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
            } else if let pni = serviceId as? Pni {
                signalRecipient = recipientFetcher.fetchOrCreate(serviceId: pni, tx: tx)
            } else {
                return nil
            }
            return threadStore.getOrCreateContactThread(with: signalRecipient.address, tx: tx).uniqueId
        case .groupMasterKey(let masterKeyData)?:
            guard let masterKey = try? GroupMasterKey(contents: masterKeyData) else {
                return nil
            }
            let groupId = GroupV2ContextInfo.deriveFrom(masterKey: masterKey).groupId
            return threadStore.fetchThread(forGroupId: groupId, tx: tx)?.uniqueId
        case .legacyGroupID(let groupId)?:
            return threadStore.fetchThread(forGroupIdData: groupId, tx: tx)?.uniqueId
        case nil:
            return nil
        }
    }
}

extension StorageService.StorageItem {
    /// The chat folder record of an item whose key has the chat folder type.
    var ivyChatFolderRecord: IvyStorageProtos_ChatFolderRecord? {
        guard identifier.type == StorageServiceChatFolderRecordUpdater.keyType else {
            return nil
        }
        guard
            let data = try? record.serializedData(),
            let chatFolder = try? IvyStorageProtos_StorageRecord(serializedBytes: data).chatFolder
        else {
            owsFailDebug("unexpectedly missing chat folder record")
            return nil
        }
        return chatFolder
    }
}

extension IvyStorageProtos_ChatFolderRecord: Codable {
    public init(from decoder: Swift.Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        try self.init(serializedBytes: data)
    }

    public func encode(to encoder: Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(try serializedData())
    }
}
