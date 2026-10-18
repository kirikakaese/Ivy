//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

@MainActor
final class IvyGlanceWriterTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testGlance() {
        let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!
        let lunch = IvyEvent(title: "Lunch", startAt: date(18, 12), endAt: date(18, 13))
        let tomorrow = IvyEvent(title: "Dentist", startAt: date(19, 9), endAt: date(19, 10))
        let dueToday = IvyTask(title: "Pay rent", dueAt: date(18, 17))
        let later = IvyTask(title: "Taxes", dueAt: date(30, 9))
        let someday = IvyTask(title: "Read book")
        let done = IvyTask(title: "Done", dueAt: date(18, 9), isDone: true)
        let reminder = IvyReminder(chat: chat, dueAt: date(18, 15))

        let glance = IvyGlanceWriter.glance(
            events: [lunch, tomorrow],
            tasks: [someday, later, dueToday, done],
            reminders: [reminder],
            reminderTitle: { _ in "Anna" },
            unreadCount: 4,
            now: date(18, 10),
            calendar: calendar,
        )
        XCTAssertEqual(glance.unreadCount, 4)
        XCTAssertEqual(glance.today.map(\.title), ["Lunch", "Anna", "Pay rent"])
        XCTAssertEqual(glance.today.first?.link, IvyLink.event(id: lunch.id).url)
        XCTAssertEqual(glance.tasks.map(\.title), ["Pay rent", "Taxes", "Read book"])
        XCTAssertEqual(glance.openTaskCount, 3)
    }
}
