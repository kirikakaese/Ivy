//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class IvyCalendarUITest: XCTestCase {

    func testAlertTitles() {
        XCTAssertFalse(IvyCalendarUI.title(forAlert: nil).isEmpty)
        XCTAssertFalse(IvyCalendarUI.title(forAlert: 0).isEmpty)
        for minutes in IvyCalendarUI.alertChoices.compactMap({ $0 }) where minutes > 0 {
            XCTAssertNotEqual(IvyCalendarUI.title(forAlert: minutes), IvyCalendarUI.title(forAlert: nil))
        }
    }

    func testTimeText() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let allDay = IvyCalendarItem(kind: .task(IvyTask(title: "a")), start: start, end: start, isAllDay: true)
        XCTAssertEqual(IvyCalendarUI.timeText(for: allDay), IvyLocalizedString("EVENT_ALL_DAY", comment: ""))

        let event = IvyEvent(title: "a", startAt: start, endAt: start.addingTimeInterval(3600))
        let timed = IvyCalendarItem(kind: .event(event), start: start, end: event.endAt, isAllDay: false)
        XCTAssertTrue(IvyCalendarUI.timeText(for: timed).contains("–"))
    }

    func testCalendarFileIsNamedAfterTheEvent() throws {
        let start = Date()
        let url = try XCTUnwrap(IvyCalendarUI.writeCalendarFile([IvyEvent(title: "Team / Lunch", startAt: start, endAt: start)]))
        XCTAssertEqual(url.lastPathComponent, "Team  Lunch.ics")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("SUMMARY:Team / Lunch"))
    }

    @MainActor
    func testEveryModeShowsTheRightDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
        let day = calendar.startOfDay(for: now)
        func interval(_ mode: IvyCalendarViewController.Mode) -> DateInterval {
            IvyCalendarViewController.visibleInterval(mode: mode, selectedDay: day, now: now, calendar: calendar)
        }

        XCTAssertEqual(interval(.day), DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!))
        XCTAssertEqual(interval(.week).start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        XCTAssertEqual(interval(.month).start, calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
        XCTAssertEqual(interval(.month).end, calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        XCTAssertEqual(interval(.agenda).start, day)
        XCTAssertEqual(interval(.agenda).end, calendar.date(byAdding: .day, value: IvyCalendarViewController.agendaDays, to: day))
    }

    @MainActor
    func testMonthViewHasWholeWeeks() {
        let monthView = IvyMonthView()
        let today = Date()
        monthView.update(month: today, selectedDay: today, daysWithItems: [], calendar: .current)
        XCTAssertEqual(monthView.dayButtons.count % 7, 0)
        XCTAssertGreaterThanOrEqual(monthView.dayButtons.count, 28)
    }
}
