//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyStarsTest: XCTestCase {

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!

    private func makeStore(deviceId: UInt32 = 1) throws -> IvyDataStore {
        try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { deviceId }))
    }

    func testStarsRoundTripNewestFirst() throws {
        let store = try makeStore()
        let older = IvyStar(
            message: IvyMessageReference(chat: chat, timestamp: 1, authorAci: nil),
            quote: "first",
            starredAt: Date(timeIntervalSince1970: 1_000),
        )
        let newer = IvyStar(
            message: IvyMessageReference(chat: chat, timestamp: 2, authorAci: "x"),
            quote: "second",
            starredAt: Date(timeIntervalSince1970: 2_000),
        )
        IvyStarStore.save(older, store: store)
        IvyStarStore.save(newer, store: store)
        XCTAssertEqual(IvyStarStore.all(store: store), [newer, older])

        IvyStarStore.delete(message: older.message, store: store)
        XCTAssertEqual(IvyStarStore.all(store: store), [newer])
    }

    func testStarringOnTwoDevicesKeepsOneStar() throws {
        let phone = try makeStore(deviceId: 1)
        let mac = try makeStore(deviceId: 2)
        var phoneChanges = [IvyDataChange]()
        phone.onLocalChanges = { phoneChanges += $0 }

        let message = IvyMessageReference(chat: chat, timestamp: 42, authorAci: nil)
        IvyStarStore.save(IvyStar(message: message, quote: "hi"), store: phone)
        IvyStarStore.save(IvyStar(message: message, quote: "hi"), store: mac)
        mac.apply(phoneChanges)

        XCTAssertEqual(IvyStarStore.all(store: mac).count, 1)
        XCTAssertEqual(IvyStar.id(for: message), IvyStar(message: message, quote: "").id)
    }

    func testChatNotes() throws {
        let store = try makeStore()
        XCTAssertEqual(IvyChatNoteStore.note(for: chat, store: store), "")

        IvyChatNoteStore.save("Birthday: 3 May", for: chat, store: store)
        XCTAssertEqual(IvyChatNoteStore.note(for: chat, store: store), "Birthday: 3 May")

        IvyChatNoteStore.save(String(repeating: "a", count: IvyChatNoteStore.maxLength + 10), for: chat, store: store)
        XCTAssertEqual(IvyChatNoteStore.note(for: chat, store: store).count, IvyChatNoteStore.maxLength)

        // An empty note is removed.
        IvyChatNoteStore.save("  \n", for: chat, store: store)
        XCTAssertEqual(IvyChatNoteStore.note(for: chat, store: store), "")
        XCTAssertTrue(store.entities(kind: IvyChatNoteStore.kind).isEmpty)
    }
}
