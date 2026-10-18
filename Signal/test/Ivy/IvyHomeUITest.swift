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
}
