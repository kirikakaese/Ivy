//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyCalendarTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func makeStore() throws -> IvyDataStore {
        try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
    }

    private let chat = IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!

    // MARK: - Recurrence

    func testWeeklyOccurrences() {
        let event = IvyEvent(
            title: "Choir",
            startAt: date(2026, 10, 5, 19),
            endAt: date(2026, 10, 5, 21),
            recurrence: IvyRecurrence(frequency: .weekly),
        )
        let october = DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1))
        XCTAssertEqual(event.occurrences(in: october, calendar: calendar), [
            date(2026, 10, 5, 19), date(2026, 10, 12, 19), date(2026, 10, 19, 19), date(2026, 10, 26, 19),
        ])
        XCTAssertEqual(event.nextStart(onOrAfter: date(2026, 10, 13), calendar: calendar), date(2026, 10, 19, 19))
    }

    func testMonthlyOnThe31stSkipsShortMonths() {
        let event = IvyEvent(
            title: "Rent",
            startAt: date(2026, 1, 31),
            endAt: date(2026, 1, 31),
            isAllDay: true,
            recurrence: IvyRecurrence(frequency: .monthly, until: date(2026, 6, 1)),
        )
        let year = DateInterval(start: date(2026, 1, 1), end: date(2027, 1, 1))
        XCTAssertEqual(event.occurrences(in: year, calendar: calendar), [date(2026, 1, 31), date(2026, 3, 31), date(2026, 5, 31)])
    }

    func testMultiDayEventIsOnEachDay() {
        let event = IvyEvent(title: "Trip", startAt: date(2026, 10, 9), endAt: date(2026, 10, 11), isAllDay: true)
        let week = DateInterval(start: date(2026, 10, 5), end: date(2026, 10, 12))
        let items = IvyCalendar.items(events: [event], tasks: [], reminders: [], in: week, calendar: calendar)
        let days = IvyCalendar.itemsByDay(items, in: week, calendar: calendar).map(\.day)
        XCTAssertEqual(days, [date(2026, 10, 9), date(2026, 10, 10), date(2026, 10, 11)])
    }

    func testItemsMixEventsTasksAndReminders() {
        let day = DateInterval(start: date(2026, 10, 17), end: date(2026, 10, 18))
        let event = IvyEvent(title: "Lunch", startAt: date(2026, 10, 17, 12), endAt: date(2026, 10, 17, 13))
        let task = IvyTask(title: "Report", dueAt: date(2026, 10, 17, 9))
        let doneTask = IvyTask(title: "Old", dueAt: date(2026, 10, 17, 9), isDone: true)
        let allDayTask = IvyTask(title: "Birthday card", dueAt: date(2026, 10, 17), isAllDay: true)
        let reminder = IvyReminder(chat: chat, dueAt: date(2026, 10, 17, 15))
        let items = IvyCalendar.items(events: [event], tasks: [task, doneTask, allDayTask], reminders: [reminder], in: day, calendar: calendar)
        XCTAssertEqual(items.map(\.start), [date(2026, 10, 17), date(2026, 10, 17, 9), date(2026, 10, 17, 12), date(2026, 10, 17, 15)])
        XCTAssertTrue(items[0].isAllDay)
    }

    func testMonthGrid() {
        let grid = IvyCalendar.monthGrid(containing: date(2026, 10, 17), calendar: calendar)
        XCTAssertEqual(grid.count % 7, 0)
        XCTAssertEqual(grid.first, date(2026, 9, 28))
        XCTAssertEqual(grid.last, date(2026, 11, 1))
    }

    // MARK: - Date detection

    func testDetectsDatesAndTimes() {
        let timed = IvyDateDetection.dates(in: "Let's meet on 12 November 2026 at 14:30 at the station")
        XCTAssertEqual(timed.count, 1)
        XCTAssertFalse(timed.first?.isAllDay ?? true)
        XCTAssertEqual(Calendar.current.component(.minute, from: timed.first!.date), 30)

        let dayOnly = IvyDateDetection.dates(in: "The party is on 12 November 2026.")
        XCTAssertEqual(dayOnly.first?.isAllDay, true)

        XCTAssertTrue(IvyDateDetection.dates(in: "No dates here").isEmpty)
        XCTAssertTrue(IvyDateDetection.namesTime("tomorrow at 3 pm"))
        XCTAssertTrue(IvyDateDetection.namesTime("morgen um 15 Uhr"))
        XCTAssertFalse(IvyDateDetection.namesTime("12 November"))
    }

    func testDraftFromDetectedDate() {
        let timed = IvyDetectedDate(date: date(2026, 11, 12, 14), duration: nil, isAllDay: false, text: "")
        let event = IvyEvent.draft(from: timed, title: "Meet", source: nil, calendar: calendar)
        XCTAssertEqual(event.endAt, date(2026, 11, 12, 15))

        let allDay = IvyDetectedDate(date: date(2026, 11, 12, 12), duration: nil, isAllDay: true, text: "")
        let allDayEvent = IvyEvent.draft(from: allDay, title: "Party", source: nil, calendar: calendar)
        XCTAssertTrue(allDayEvent.isAllDay)
        XCTAssertEqual(allDayEvent.startAt, date(2026, 11, 12))
    }

    // MARK: - ICS

    func testExportAndImportRoundTrip() throws {
        let events = [
            IvyEvent(
                title: "Dinner; with, friends",
                notes: "Bring\ndessert",
                location: "Café Ivy",
                startAt: date(2026, 11, 12, 19),
                endAt: date(2026, 11, 12, 22),
                recurrence: IvyRecurrence(frequency: .weekly, interval: 2, until: date(2026, 12, 31, 23, 59)),
                alertMinutes: 30,
            ),
            IvyEvent(title: "Holiday", startAt: date(2026, 12, 24), endAt: date(2026, 12, 26), isAllDay: true),
        ]
        let text = IvyICS.export(events, now: date(2026, 10, 17), calendar: calendar)
        XCTAssertTrue(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(text.contains("DTEND;VALUE=DATE:20261227"))
        for line in text.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.utf8.count, 75)
        }

        let parsed = try IvyICS.parse(text, calendar: calendar)
        XCTAssertEqual(parsed.count, 2)
        let dinner = parsed[0]
        XCTAssertEqual(dinner.title, "Dinner; with, friends")
        XCTAssertEqual(dinner.notes, "Bring\ndessert")
        XCTAssertEqual(dinner.location, "Café Ivy")
        XCTAssertEqual(dinner.startAt, date(2026, 11, 12, 19))
        XCTAssertEqual(dinner.endAt, date(2026, 11, 12, 22))
        XCTAssertEqual(dinner.recurrence?.frequency, .weekly)
        XCTAssertEqual(dinner.recurrence?.interval, 2)
        XCTAssertEqual(dinner.alertMinutes, 30)
        XCTAssertEqual(dinner.importedUID, "\(events[0].id)@ivy")

        let holiday = parsed[1]
        XCTAssertTrue(holiday.isAllDay)
        XCTAssertEqual(holiday.startAt, date(2026, 12, 24))
        XCTAssertEqual(holiday.endAt, date(2026, 12, 26))
    }

    func testImportsOtherCalendarApps() throws {
        let text = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        PRODID:-//Example//EN\r
        BEGIN:VTIMEZONE\r
        TZID:America/New_York\r
        END:VTIMEZONE\r
        BEGIN:VEVENT\r
        UID:abc-123\r
        DTSTART;TZID=America/New_York:20261112T090000\r
        DURATION:PT1H30M\r
        SUMMARY:Stand-up with a very long title that goes on and on so that the\r
          line is folded\r
        RRULE:FREQ=DAILY;COUNT=3\r
        BEGIN:VALARM\r
        TRIGGER:-PT1H\r
        ACTION:DISPLAY\r
        END:VALARM\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:no-time\r
        DTSTART;VALUE=DATE:20261201\r
        SUMMARY:Deadline\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Broken, no start\r
        END:VEVENT\r
        END:VCALENDAR\r

        """
        let events = try IvyICS.parse(text, calendar: calendar)
        XCTAssertEqual(events.count, 2)

        let standUp = events[0]
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(standUp.startAt, newYork.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9)))
        XCTAssertEqual(standUp.endAt.timeIntervalSince(standUp.startAt), 90 * 60)
        XCTAssertEqual(standUp.title, "Stand-up with a very long title that goes on and on so that the line is folded")
        XCTAssertEqual(standUp.alertMinutes, 60)
        XCTAssertEqual(standUp.occurrences(in: DateInterval(start: date(2026, 11, 1), end: date(2026, 12, 1)), calendar: calendar).count, 3)

        let deadline = events[1]
        XCTAssertTrue(deadline.isAllDay)
        XCTAssertEqual(deadline.startAt, date(2026, 12, 1))
        XCTAssertEqual(deadline.endAt, date(2026, 12, 1))
    }

    func testRejectsFilesThatArentCalendars() {
        XCTAssertThrowsError(try IvyICS.parse("hello", calendar: calendar))
    }

    func testDurations() {
        XCTAssertEqual(IvyICS.parseDuration("PT15M"), 15 * 60)
        XCTAssertEqual(IvyICS.parseDuration("-P1D"), -86_400)
        XCTAssertEqual(IvyICS.parseDuration("P1W"), 7 * 86_400)
        XCTAssertEqual(IvyICS.parseDuration("P1DT2H"), 86_400 + 7200)
        XCTAssertNil(IvyICS.parseDuration("15M"))
    }

    // MARK: - Store

    func testStoreRoundTripAndImportUpdatesByUID() throws {
        let store = try makeStore()
        let message = IvyMessageReference(chat: chat, timestamp: 1, authorAci: nil)
        let event = IvyEvent(
            title: "Lunch",
            location: "Canteen",
            startAt: date(2026, 10, 17, 12),
            endAt: date(2026, 10, 17, 13),
            recurrence: IvyRecurrence(frequency: .yearly),
            alertMinutes: 15,
            source: .init(message: message, quote: "Lunch at 12?"),
            createdAt: date(2026, 10, 1),
        )
        IvyEventStore.save(event, store: store)
        XCTAssertEqual(IvyEventStore.event(id: event.id, store: store), event)

        let imported = IvyEvent(title: "Meeting", startAt: date(2026, 10, 20, 9), endAt: date(2026, 10, 20, 10), importedUID: "uid-1")
        XCTAssertEqual(IvyEventStore.importEvents([imported], store: store).added, 1)
        var moved = imported
        moved.startAt = date(2026, 10, 21, 9)
        moved.endAt = date(2026, 10, 21, 10)
        let again = IvyEventStore.importEvents([IvyEvent(title: "Meeting", startAt: moved.startAt, endAt: moved.endAt, importedUID: "uid-1")], store: store)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.updated, 1)
        XCTAssertEqual(IvyEventStore.all(store: store).filter { $0.importedUID == "uid-1" }.map(\.startAt), [date(2026, 10, 21, 9)])

        IvyEventStore.removeSources([message], store: store)
        XCTAssertNil(IvyEventStore.event(id: event.id, store: store)?.source)
        XCTAssertEqual(IvyEventStore.event(id: event.id, store: store)?.title, "Lunch")
    }

    func testAlertsAreScheduledForTheNextOccurrence() {
        let now = date(2026, 10, 17, 10)
        let weekly = IvyEvent(
            title: "Choir",
            startAt: date(2026, 10, 5, 19),
            endAt: date(2026, 10, 5, 21),
            recurrence: IvyRecurrence(frequency: .weekly),
            alertMinutes: 30,
        )
        let silent = IvyEvent(title: "Silent", startAt: date(2026, 10, 18), endAt: date(2026, 10, 18))
        let past = IvyEvent(title: "Past", startAt: date(2026, 10, 1), endAt: date(2026, 10, 1), alertMinutes: 0)
        let scheduled = IvyEventNotifications.scheduled([weekly, silent, past], after: now, calendar: calendar)
        XCTAssertEqual(scheduled.map(\.event.title), ["Choir"])
        XCTAssertEqual(scheduled.first?.start, date(2026, 10, 19, 19))
        XCTAssertEqual(scheduled.first?.alertAt, date(2026, 10, 19, 18, 30))
    }
}
