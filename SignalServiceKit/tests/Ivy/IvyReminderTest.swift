//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyReminderTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!

    private func makeStore() throws -> IvyDataStore {
        try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
    }

    func testPresets() {
        // Saturday, 17 Oct 2026, 10:00
        let now = date(2026, 10, 17, 10)
        XCTAssertEqual(IvyReminder.Preset.twentyMinutes.dueDate(from: now, calendar: calendar), date(2026, 10, 17, 10, 20))
        XCTAssertEqual(IvyReminder.Preset.threeHours.dueDate(from: now, calendar: calendar), date(2026, 10, 17, 13))
        XCTAssertEqual(IvyReminder.Preset.laterToday.dueDate(from: now, calendar: calendar), date(2026, 10, 17, 14))
        XCTAssertEqual(IvyReminder.Preset.tonight.dueDate(from: now, calendar: calendar), date(2026, 10, 17, 20))
        XCTAssertEqual(IvyReminder.Preset.tomorrowMorning.dueDate(from: now, calendar: calendar), date(2026, 10, 18, 8))
        XCTAssertEqual(IvyReminder.Preset.nextWeek.dueDate(from: now, calendar: calendar), date(2026, 10, 19, 8))
    }

    func testEveningPresets() {
        let evening = date(2026, 10, 17, 21)
        XCTAssertNil(IvyReminder.Preset.laterToday.dueDate(from: evening, calendar: calendar))
        XCTAssertNil(IvyReminder.Preset.tonight.dueDate(from: evening, calendar: calendar))
        XCTAssertNotNil(IvyReminder.Preset.tomorrowMorning.dueDate(from: evening, calendar: calendar))
    }

    func testRepeats() {
        var reminder = IvyReminder(chat: chat, dueAt: date(2026, 10, 17, 9), repeats: .daily)
        XCTAssertEqual(reminder.nextDueDate(after: date(2026, 10, 17, 10), calendar: calendar), date(2026, 10, 18, 9))
        reminder.repeats = .weekly
        XCTAssertEqual(reminder.nextDueDate(after: date(2026, 10, 17, 10), calendar: calendar), date(2026, 10, 24, 9))
        reminder.repeats = .monthly
        XCTAssertEqual(reminder.nextDueDate(after: date(2026, 12, 1, 0), calendar: calendar), date(2026, 12, 17, 9))
        reminder.repeats = .never
        XCTAssertNil(reminder.nextDueDate(after: date(2026, 10, 17, 10), calendar: calendar))
    }

    func testStoreRoundTrip() throws {
        let store = try makeStore()
        let message = IvyMessageReference(chat: chat, timestamp: 1_760_000_000_000, authorAci: nil)
        let reminder = IvyReminder(chat: chat, message: message, dueAt: Date(timeIntervalSince1970: 1_800_000_000), repeats: .weekly)
        IvyReminderStore.save(reminder, store: store)
        XCTAssertEqual(IvyReminderStore.reminder(id: reminder.id, store: store), reminder)

        var done = reminder
        done.isDone = true
        IvyReminderStore.save(done, store: store)
        XCTAssertEqual(IvyReminderStore.all(store: store), [done])
        XCTAssertTrue(IvyReminderStore.open(store: store).isEmpty)

        IvyReminderStore.delete(id: reminder.id, store: store)
        XCTAssertTrue(IvyReminderStore.all(store: store).isEmpty)
    }

    func testOnlyChangedFieldsAreWritten() throws {
        let store = try makeStore()
        var changes = [IvyDataChange]()
        store.onLocalChanges = { changes += $0 }
        var reminder = IvyReminder(chat: chat, dueAt: Date(timeIntervalSince1970: 1_800_000_000))
        IvyReminderStore.save(reminder, store: store)
        changes = []
        reminder.dueAt = Date(timeIntervalSince1970: 1_800_003_600)
        IvyReminderStore.save(reminder, store: store)
        XCTAssertEqual(changes.map(\.field), ["dueAt"])
    }

    func testChatReferences() {
        XCTAssertNotNil(IvyChatReference(rawValue: "g:AAAA"))
        XCTAssertNotNil(IvyChatReference(rawValue: "e:+15555550100"))
        XCTAssertNil(IvyChatReference(rawValue: "x:1"))
        XCTAssertNil(IvyChatReference(rawValue: "a:"))
        let decoded = IvyDataStore.decode(IvyChatReference.self, from: IvyDataStore.encode(chat))
        XCTAssertEqual(decoded, chat)
    }

    func testFolderExtrasRoundTrip() throws {
        let store = try makeStore()
        let folderId = ChatFolder.newId()
        XCTAssertEqual(ChatFolderExtras.fetch(folderId: folderId, store: store), ChatFolderExtras())

        let extras = ChatFolderExtras(emoji: "🌿", color: .green, pinnedChats: [chat])
        extras.save(folderId: folderId, comparedTo: ChatFolderExtras(), store: store)
        XCTAssertEqual(ChatFolderExtras.fetch(folderId: folderId, store: store), extras)
        XCTAssertEqual(ChatFolderExtras.fetchAll(store: store), [folderId: extras])

        ChatFolderExtras.delete(folderId: folderId, store: store)
        XCTAssertEqual(ChatFolderExtras.fetch(folderId: folderId, store: store), ChatFolderExtras())
    }

    func testChatListOrder() {
        let order = ChatFolderChats.order(
            pinned: ["p1", "p2"],
            visible: ["c1", "c2", "c3", "p1", "p2", "f1"],
            folderPinned: ["f1", "p2"],
            due: ["c3", "p1", "gone"],
        )
        XCTAssertEqual(order.pinned, ["f1", "p2", "p1"])
        XCTAssertEqual(order.visible, ["c3", "c1", "c2", "p1", "p2", "f1"])
    }
}
