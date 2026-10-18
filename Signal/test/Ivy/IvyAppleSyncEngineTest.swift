//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import EventKit
import SignalServiceKit
import XCTest

@testable import Signal

@MainActor
final class IvyAppleSyncEngineTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testEventRoundTrip() {
        let fields = IvyAppleEventFields(
            title: "Team lunch",
            notes: "Bring the slides",
            location: "Canteen",
            startAt: date(2026, 10, 20, 12),
            endAt: date(2026, 10, 20, 13),
            isAllDay: false,
            recurrence: IvyRecurrence(frequency: .weekly, interval: 2, until: date(2026, 12, 31)),
        )
        let event = EKEvent(eventStore: EKEventStore())
        IvyAppleSyncEngine.write(fields, to: event)
        XCTAssertEqual(IvyAppleSyncEngine.fields(of: event, calendar: calendar), fields)
    }

    func testAllDayEventEndsOnItsLastDay() {
        let event = EKEvent(eventStore: EKEventStore())
        event.isAllDay = true
        event.startDate = date(2026, 10, 20)
        // Apple ends an all-day event at the end of its last day.
        event.endDate = date(2026, 10, 22, 23, 59)
        XCTAssertEqual(IvyAppleSyncEngine.fields(of: event, calendar: calendar).endAt, date(2026, 10, 22))

        event.endDate = date(2026, 10, 23)
        XCTAssertEqual(IvyAppleSyncEngine.fields(of: event, calendar: calendar).endAt, date(2026, 10, 22))
    }

    func testReminderRoundTrip() {
        let store = EKEventStore()
        let timed = IvyAppleReminderFields(
            title: "Call Anna",
            notes: "About Friday",
            dueAt: date(2026, 10, 20, 17, 30),
            isAllDay: false,
            priority: .medium,
            isDone: false,
        )
        let reminder = EKReminder(eventStore: store)
        IvyAppleSyncEngine.write(timed, to: reminder, calendar: calendar)
        XCTAssertEqual(IvyAppleSyncEngine.fields(of: reminder, calendar: calendar), timed)

        let allDay = IvyAppleReminderFields(title: "Taxes", notes: "", dueAt: date(2026, 10, 31), isAllDay: true, priority: .none, isDone: true)
        IvyAppleSyncEngine.write(allDay, to: reminder, calendar: calendar)
        XCTAssertNil(reminder.dueDateComponents?.hour)
        XCTAssertEqual(IvyAppleSyncEngine.fields(of: reminder, calendar: calendar), allDay)
    }
}
