//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyStorageServiceTest: XCTestCase {

    /// A `StorageRecord` with a chat folder, encoded with Signal's official
    /// StorageService.proto.
    private let officialStorageRecord = Data(hex: "426c0a10000102030405060708090a0b0c0d0e0f1204576f726b18022001380140024a140a121a10111111111111111111111111111111114a221a20222222222222222222222222222222222222222222222222222222222222222252100a0e120c2b3135353535353530313030")!

    /// A deleted chat folder, encoded with Signal's official
    /// StorageService.proto.
    private let officialDeletedFolder = Data(hex: "0a10000102030405060708090a0b0c0d0e0f18ffffffff0f4002588080b3c19c33")!

    private func makeFolderRecord() -> IvyStorageProtos_ChatFolderRecord {
        var record = IvyStorageProtos_ChatFolderRecord()
        record.identifier = Data(0..<16)
        record.name = "Work"
        record.position = 2
        record.showOnlyUnread = true
        record.includeAllGroupChats = true
        record.folderType = .custom
        var contact = IvyStorageProtos_Recipient.Contact()
        contact.serviceIDBinary = Data(repeating: 0x11, count: 16)
        var contactRecipient = IvyStorageProtos_Recipient()
        contactRecipient.identifier = .contact(contact)
        var groupRecipient = IvyStorageProtos_Recipient()
        groupRecipient.identifier = .groupMasterKey(Data(repeating: 0x22, count: 32))
        var phoneNumber = IvyStorageProtos_Recipient.Contact()
        phoneNumber.e164 = "+15555550100"
        var excludedRecipient = IvyStorageProtos_Recipient()
        excludedRecipient.identifier = .contact(phoneNumber)
        record.includedRecipients = [contactRecipient, groupRecipient]
        record.excludedRecipients = [excludedRecipient]
        return record
    }

    func testEncodesLikeTheOfficialProto() throws {
        var storageRecord = IvyStorageProtos_StorageRecord()
        storageRecord.chatFolder = makeFolderRecord()
        XCTAssertEqual(try storageRecord.serializedData(), officialStorageRecord)
    }

    func testDecodesTheOfficialProto() throws {
        let storageRecord = try IvyStorageProtos_StorageRecord(serializedBytes: officialStorageRecord)
        XCTAssertEqual(storageRecord.chatFolder, makeFolderRecord())

        let deleted = try IvyStorageProtos_ChatFolderRecord(serializedBytes: officialDeletedFolder)
        XCTAssertEqual(deleted.position, UInt32.max)
        XCTAssertEqual(deleted.deletedAtTimestampMs, 1_760_000_000_000)
        XCTAssertEqual(deleted.folderType, .custom)
    }

    func testUpstreamRecordKeepsTheFolderUnchanged() throws {
        let upstream = try StorageServiceProtoStorageRecord(serializedData: officialStorageRecord)
        XCTAssertNil(upstream.record)
        XCTAssertEqual(try upstream.serializedData(), officialStorageRecord)
    }

    func testStorageItemRoundTrip() throws {
        let updater = StorageServiceChatFolderRecordUpdater(
            chatFolderManager: ChatFolderManager(store: KeyValueStore(collection: "IvyStorageServiceTest")),
            recipientDatabaseTable: RecipientDatabaseTable(),
            recipientFetcher: RecipientFetcher(
                recipientDatabaseTable: RecipientDatabaseTable(),
                searchableNameIndexer: MockSearchableNameIndexer(),
            ),
            threadStore: MockThreadStore(),
        )
        let item = updater.buildStorageItem(for: makeFolderRecord())
        XCTAssertEqual(item.identifier.type, .UNRECOGNIZED(8))
        XCTAssertEqual(item.ivyChatFolderRecord, makeFolderRecord())
        XCTAssertNil(item.callLinkRecord)
    }

    func testUnknownFieldsAreKept() throws {
        var record = makeFolderRecord()
        // Field 99, varint 1.
        let withUnknownField = try record.serializedData() + Data([0x98, 0x06, 0x01])
        record = try IvyStorageProtos_ChatFolderRecord(serializedBytes: withUnknownField)
        XCTAssertFalse(record.unknownFields.data.isEmpty)
        XCTAssertEqual(try record.serializedData(), withUnknownField)

        let decoded = try JSONDecoder().decode(IvyStorageProtos_ChatFolderRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }
}
