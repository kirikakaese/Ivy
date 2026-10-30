//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class IvyHomeUITest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @MainActor
    func testHomeShowsSoonTasksThenUndatedOnes() {
        let now = date(2026, 10, 17, 10)
        let overdue = IvyTask(title: "overdue", dueAt: date(2026, 10, 15))
        let today = IvyTask(title: "today", dueAt: date(2026, 10, 17, 18))
        let nextWeek = IvyTask(title: "next week", dueAt: date(2026, 10, 23, 9))
        let later = IvyTask(title: "later", dueAt: date(2026, 11, 30))
        let undated = IvyTask(title: "undated")
        let done = IvyTask(title: "done", dueAt: date(2026, 10, 17, 9), isDone: true)
        let tasks = [overdue, today, nextWeek, later, undated, done].sorted(by: IvyTask.areInIncreasingOrder)

        let shown = IvyHomeViewController.homeTasks(tasks, now: now, calendar: calendar)
        XCTAssertEqual(shown.map(\.title), ["overdue", "today", "next week", "undated"])

        let many = (0..<10).map { IvyTask(title: "\($0)") }
        XCTAssertEqual(IvyHomeViewController.homeTasks(many, now: now, calendar: calendar).count, IvyHomeViewController.maxTasks)
    }

    func testSectionsMapToTabs() {
        XCTAssertEqual(HomeTabBarController.Tabs(IvySection.home), .home)
        XCTAssertEqual(HomeTabBarController.Tabs(IvySection.chats), .chatList)
        XCTAssertEqual(HomeTabBarController.Tabs(IvySection.calendar), .calendar)
        XCTAssertEqual(HomeTabBarController.Tabs(IvySection.calls), .calls)
        for tab in [HomeTabBarController.Tabs.home, .calendar, .chatList, .calls] {
            XCTAssertFalse(tab.title.isEmpty)
            XCTAssertNotNil(tab.image)
        }
    }

    @MainActor
    func testEveryReasonHasATitle() {
        let reasons: [IvyImportantMessage.Reason] = [.reminder, .mention, .reply, .importantChat, .pinnedChat]
        XCTAssertEqual(Set(reasons.map(IvyHomeViewController.title(for:))).count, reasons.count)
        for reason in reasons {
            XCTAssertFalse(IvyHomeViewController.title(for: reason).isEmpty)
        }
    }

    @MainActor
    func testNextUpIsWhatsHappeningNowOrNext() {
        let now = date(2026, 10, 30, 19)
        func event(_ title: String, _ start: Date, _ end: Date) -> IvyCalendarItem {
            IvyCalendarItem(kind: .event(IvyEvent(title: title, startAt: start, endAt: end)), start: start, end: end, isAllDay: false)
        }
        let past = event("past", date(2026, 10, 30, 9), date(2026, 10, 30, 10))
        let running = event("running", date(2026, 10, 30, 18), date(2026, 10, 30, 20))
        let later = event("later", date(2026, 10, 30, 21), date(2026, 10, 30, 22))
        let tomorrow = event("tomorrow", date(2026, 10, 31, 9), date(2026, 10, 31, 10))
        let allDay = IvyCalendarItem(kind: .event(IvyEvent(title: "all day", startAt: now, endAt: now)), start: date(2026, 10, 30), end: date(2026, 10, 31), isAllDay: true)

        let next = IvyHomeViewController.nextUp([tomorrow, later, past, allDay, running], now: now, calendar: calendar)
        XCTAssertEqual(next.map { title($0.item) }, "running")
        XCTAssertEqual(next?.following.map(title), "later")

        let onlyTomorrow = IvyHomeViewController.nextUp([past, tomorrow], now: now, calendar: calendar)
        XCTAssertEqual(onlyTomorrow.map { title($0.item) }, "tomorrow")
        XCTAssertNil(onlyTomorrow?.following, "the next day's items don't follow")
        XCTAssertNil(IvyHomeViewController.nextUp([past, allDay], now: now, calendar: calendar))

        XCTAssertEqual(IvyHomeHeaderView.when(running, now: now, calendar: calendar), IvyLocalizedString("HOME_NEXT_NOW", comment: ""))
        XCTAssertEqual(IvyHomeHeaderView.when(tomorrow, now: now, calendar: calendar), IvyLocalizedString("HOME_NEXT_TOMORROW", comment: ""))
        XCTAssertTrue(IvyHomeHeaderView.when(later, now: now, calendar: calendar).contains("2"))
    }

    private func title(_ item: IvyCalendarItem) -> String {
        if case .event(let event) = item.kind {
            return event.title
        }
        return ""
    }

    @MainActor
    func testGreetingFollowsTheTimeOfDay() {
        let greetings = [6, 13, 20, 2].map { IvyHomeHeaderView.greeting(at: date(2026, 10, 30, $0), calendar: calendar) }
        XCTAssertEqual(Set(greetings).count, 4)
        XCTAssertEqual(IvyHomeHeaderView.greeting(at: date(2026, 10, 30, 23), calendar: calendar), greetings[3])
    }

    @MainActor
    func testEveryReasonHasATone() {
        XCTAssertEqual(IvyHomeViewController.tone(for: .mention), .blue)
        XCTAssertEqual(IvyHomeViewController.tone(for: .reply), .brown)
    }
}
