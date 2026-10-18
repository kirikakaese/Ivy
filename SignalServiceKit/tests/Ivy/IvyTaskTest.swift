//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyTaskTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!

    private func makeStore(deviceId: UInt32 = 1) throws -> IvyDataStore {
        try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { deviceId }))
    }

    // MARK: - Model

    func testGroups() {
        // Saturday, 17 Oct 2026, 10:00
        let now = date(2026, 10, 17, 10)
        XCTAssertEqual(IvyTask(title: "a").group(at: now, calendar: calendar), .someday)
        XCTAssertEqual(IvyTask(title: "a", dueAt: date(2026, 10, 17, 9)).group(at: now, calendar: calendar), .overdue)
        XCTAssertEqual(IvyTask(title: "a", dueAt: date(2026, 10, 17, 18)).group(at: now, calendar: calendar), .today)
        XCTAssertEqual(IvyTask(title: "a", dueAt: date(2026, 10, 18, 9)).group(at: now, calendar: calendar), .upcoming)
        // An all-day task due today isn't overdue until tomorrow.
        XCTAssertEqual(IvyTask(title: "a", dueAt: date(2026, 10, 17), isAllDay: true).group(at: now, calendar: calendar), .today)
        XCTAssertEqual(IvyTask(title: "a", dueAt: date(2026, 10, 16), isAllDay: true).group(at: now, calendar: calendar), .overdue)
        XCTAssertEqual(IvyTask(title: "a", dueAt: date(2026, 10, 16), isDone: true).group(at: now, calendar: calendar), .done)
    }

    func testReminderDate() {
        let timed = IvyTask(title: "a", dueAt: date(2026, 10, 17, 14, 30), reminds: true)
        XCTAssertEqual(timed.reminderDate(calendar: calendar), date(2026, 10, 17, 14, 30))

        let allDay = IvyTask(title: "a", dueAt: date(2026, 10, 17), isAllDay: true, reminds: true)
        XCTAssertEqual(allDay.reminderDate(calendar: calendar), date(2026, 10, 17, IvyTask.allDayReminderHour))

        XCTAssertNil(IvyTask(title: "a", dueAt: date(2026, 10, 17, 14)).reminderDate(calendar: calendar))
        XCTAssertNil(IvyTask(title: "a", dueAt: date(2026, 10, 17, 14), reminds: true, isDone: true).reminderDate(calendar: calendar))
        XCTAssertNil(IvyTask(title: "a", reminds: true).reminderDate(calendar: calendar))
    }

    func testOnlyFutureRemindersAreScheduled() {
        let now = date(2026, 10, 17, 10)
        let past = IvyTask(title: "past", dueAt: date(2026, 10, 17, 9), reminds: true)
        let future = IvyTask(title: "future", dueAt: date(2026, 10, 17, 11), reminds: true)
        let silent = IvyTask(title: "silent", dueAt: date(2026, 10, 17, 11))
        let scheduled = IvyTaskNotifications.scheduled([past, future, silent], after: now, calendar: calendar)
        XCTAssertEqual(scheduled.map(\.0.title), ["future"])
        XCTAssertEqual(scheduled.first?.1, date(2026, 10, 17, 11))
    }

    func testTitleAndQuoteFromMessage() {
        XCTAssertEqual(IvyTask.title(fromMessageText: "\n  Buy milk  \nand bread"), "Buy milk")
        XCTAssertEqual(IvyTask.title(fromMessageText: ""), "")
        let long = String(repeating: "a", count: 600)
        XCTAssertEqual(IvyTask.title(fromMessageText: long).count, IvyTask.maxTitleLength)
        XCTAssertTrue(IvyTask.title(fromMessageText: long).hasSuffix("…"))
        XCTAssertEqual(IvyTask.quote(fromMessageText: long).count, IvyTask.maxQuoteLength)
        XCTAssertEqual(IvyTask.quote(fromMessageText: " short "), "short")
    }

    func testOrder() {
        let soon = IvyTask(title: "soon", dueAt: date(2026, 10, 17, 9))
        let later = IvyTask(title: "later", dueAt: date(2026, 10, 18, 9))
        let urgent = IvyTask(title: "urgent", priority: .high, createdAt: date(2026, 10, 1))
        let plain = IvyTask(title: "plain", createdAt: date(2026, 10, 2))
        let sorted = [plain, later, urgent, soon].sorted(by: IvyTask.areInIncreasingOrder)
        XCTAssertEqual(sorted.map(\.title), ["soon", "later", "urgent", "plain"])
    }

    func testSubtaskProgress() {
        var task = IvyTask(title: "a", subtasks: [.init(title: "1", isDone: true), .init(title: "2")])
        XCTAssertEqual(task.subtaskProgress.done, 1)
        XCTAssertEqual(task.subtaskProgress.total, 2)
        task.setDone(true, at: date(2026, 10, 17))
        XCTAssertEqual(task.completedAt, date(2026, 10, 17))
        task.setDone(false)
        XCTAssertNil(task.completedAt)
    }

    // MARK: - Store

    func testStoreRoundTrip() throws {
        let store = try makeStore()
        let message = IvyMessageReference(chat: chat, timestamp: 1_760_000_000_000, authorAci: nil)
        let task = IvyTask(
            title: "Buy milk",
            notes: "Oat milk",
            dueAt: date(2026, 10, 18),
            isAllDay: true,
            reminds: true,
            listId: "list",
            priority: .medium,
            subtasks: [.init(title: "1"), .init(title: "2", isDone: true)],
            source: .init(message: message, quote: "Can you buy milk?"),
            createdAt: date(2026, 10, 17, 10),
        )
        IvyTaskStore.save(task, store: store)
        XCTAssertEqual(IvyTaskStore.task(id: task.id, store: store), task)

        var done = task
        done.setDone(true, at: date(2026, 10, 17, 11))
        IvyTaskStore.save(done, store: store)
        XCTAssertEqual(IvyTaskStore.all(store: store), [done])

        IvyTaskStore.delete(id: task.id, store: store)
        XCTAssertTrue(IvyTaskStore.all(store: store).isEmpty)
    }

    func testEditsOnTwoDevicesMergeByField() throws {
        let phone = try makeStore(deviceId: 1)
        let mac = try makeStore(deviceId: 2)
        var sent = [IvyDataChange]()
        phone.onLocalChanges = { sent += $0 }

        let task = IvyTask(title: "Call Anna", createdAt: date(2026, 10, 17))
        IvyTaskStore.save(task, store: phone)
        mac.apply(sent)
        sent = []

        // The phone renames the task while the Mac finishes it.
        var renamed = task
        renamed.title = "Call Anna back"
        IvyTaskStore.save(renamed, store: phone)
        var finished = task
        finished.setDone(true, at: date(2026, 10, 17, 12))
        var macChanges = [IvyDataChange]()
        mac.onLocalChanges = { macChanges += $0 }
        IvyTaskStore.save(finished, store: mac)

        mac.apply(sent)
        phone.apply(macChanges)

        for store in [phone, mac] {
            let merged = IvyTaskStore.task(id: task.id, store: store)
            XCTAssertEqual(merged?.title, "Call Anna back")
            XCTAssertEqual(merged?.isDone, true)
        }
    }

    func testRemovingSources() throws {
        let store = try makeStore()
        let gone = IvyMessageReference(chat: chat, timestamp: 1, authorAci: nil)
        let kept = IvyMessageReference(chat: chat, timestamp: 2, authorAci: nil)
        let first = IvyTask(title: "first", notes: "keep me", source: .init(message: gone, quote: "quote"))
        let second = IvyTask(title: "second", source: .init(message: kept, quote: "quote"))
        IvyTaskStore.save(first, store: store)
        IvyTaskStore.save(second, store: store)

        let changed = IvyTaskStore.removeSources([gone], store: store)
        XCTAssertEqual(changed.map(\.id), [first.id])
        XCTAssertNil(IvyTaskStore.task(id: first.id, store: store)?.source)
        XCTAssertEqual(IvyTaskStore.task(id: first.id, store: store)?.notes, "keep me")
        XCTAssertEqual(IvyTaskStore.task(id: second.id, store: store)?.source?.message, kept)
    }

    func testDeletingAListKeepsItsTasks() throws {
        let store = try makeStore()
        let work = IvyTaskList(name: "Work")
        let home = IvyTaskList(name: "home")
        IvyTaskStore.save(work, store: store)
        IvyTaskStore.save(home, store: store)
        XCTAssertEqual(IvyTaskStore.lists(store: store).map(\.name), ["home", "Work"])

        let task = IvyTask(title: "Report", listId: work.id)
        IvyTaskStore.save(task, store: store)
        IvyTaskStore.delete(list: work, store: store)

        XCTAssertEqual(IvyTaskStore.lists(store: store), [home])
        XCTAssertEqual(IvyTaskStore.task(id: task.id, store: store)?.title, "Report")
        XCTAssertNil(IvyTaskStore.task(id: task.id, store: store)?.listId)
    }
}
