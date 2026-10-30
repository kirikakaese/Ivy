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
        monthView.update(month: today, selectedDay: today, tones: [:], calendar: .current)
        XCTAssertEqual(monthView.dayButtons.count % 7, 0)
        XCTAssertGreaterThanOrEqual(monthView.dayButtons.count, 28)
    }

    @MainActor
    func testOverlappingItemsShareTheWidth() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func item(_ startHours: Double, _ endHours: Double) -> IvyCalendarItem {
            let start = base.addingTimeInterval(startHours * 3600)
            let end = base.addingTimeInterval(endHours * 3600)
            return IvyCalendarItem(kind: .event(IvyEvent(title: "", startAt: start, endAt: end)), start: start, end: end, isAllDay: false)
        }
        let placed = IvyDayTimelineView.columns(for: [item(0, 2), item(1, 3), item(4, 5), item(1.5, 1.5)])
        XCTAssertEqual(placed.count, 4)
        let alone = placed.first { $0.item.start == base.addingTimeInterval(4 * 3600) }
        XCTAssertEqual(alone?.columns, 1, "an item that overlaps nothing takes the whole width")
        let overlapping = placed.filter { $0.item.start < base.addingTimeInterval(4 * 3600) }
        XCTAssertEqual(Set(overlapping.map(\.columns)), [3])
        XCTAssertEqual(Set(overlapping.map(\.column)).count, 3)
    }

    func testDayHeadingsAreRelativeNearToday() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        XCTAssertNotNil(IvyCalendarUI.dayHeading(today).detail)
        let later = calendar.date(byAdding: .day, value: 10, to: today)!
        XCTAssertNil(IvyCalendarUI.dayHeading(later).detail)
        let allDay = IvyCalendarItem(kind: .task(IvyTask(title: "a")), start: today, end: today, isAllDay: true)
        XCTAssertEqual(IvyCalendarUI.shortTimeText(for: allDay), IvyLocalizedString("EVENT_ALL_DAY", comment: ""))
    }

    func testDotsFollowTheKindsOfItems() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date().addingTimeInterval(86_400 * 3))
        let event = IvyEvent(title: "e", startAt: day.addingTimeInterval(3600), endAt: day.addingTimeInterval(7200))
        let items = [
            IvyCalendarItem(kind: .task(IvyTask(title: "t", dueAt: day.addingTimeInterval(1800))), start: day.addingTimeInterval(1800), end: day.addingTimeInterval(1800), isAllDay: false),
            IvyCalendarItem(kind: .event(event), start: event.startAt, end: event.endAt, isAllDay: false),
        ]
        let tones = IvyCalendar.tonesByDay(items, in: DateInterval(start: day, duration: 86_400), calendar: calendar)
        XCTAssertEqual(tones[day], [.blue, .green])
    }
}
