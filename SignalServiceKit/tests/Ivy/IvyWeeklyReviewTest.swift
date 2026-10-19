//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyWeeklyReviewTest: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testSortsTasksAndEventsIntoTheWeek() {
        let now = date(day: 19)
        let overdue = IvyTask(id: "a", title: "Overdue", dueAt: date(day: 17))
        let soon = IvyTask(id: "b", title: "Soon", dueAt: date(day: 21))
        let later = IvyTask(id: "c", title: "Later", dueAt: date(day: 30))
        let someday = IvyTask(id: "d", title: "Someday")
        let done = IvyTask(id: "e", title: "Done", dueAt: date(day: 18), isDone: true)
        let event = IvyEvent(title: "Dinner", startAt: date(day: 22, hour: 19), endAt: date(day: 22, hour: 21))
        let farEvent = IvyEvent(title: "Trip", startAt: date(day: 29), endAt: date(day: 29, hour: 14))

        let contents = IvyWeeklyReview.contents(
            tasks: [later, someday, done, soon, overdue],
            events: [farEvent, event],
            now: now,
            calendar: calendar,
        )
        XCTAssertEqual(contents.overdueTasks.map(\.id), ["a"])
        XCTAssertEqual(contents.dueTasks.map(\.id), ["b"])
        XCTAssertEqual(contents.somedayTasks.map(\.id), ["d"])
        XCTAssertEqual(contents.events.count, 1)
    }

    func testTaskFromTranscript() {
        let task = IvyTask.fromTranscript("Call the dentist. Ask about Thursday afternoon", message: nil)
        XCTAssertEqual(task.title, "Call the dentist")
        XCTAssertEqual(task.notes, "Call the dentist. Ask about Thursday afternoon")

        let short = IvyTask.fromTranscript("Buy milk", message: nil)
        XCTAssertEqual(short.title, "Buy milk")
        XCTAssertEqual(short.notes, "")
    }
}
