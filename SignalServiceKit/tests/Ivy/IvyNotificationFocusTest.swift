//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvyNotificationFocusTest: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// 2026-10-19 is a Monday.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testWorkdayHours() {
        let hours = IvyNotificationHours.workdays
        XCTAssertTrue(hours.allows(date(day: 19, hour: 9), calendar: calendar))
        XCTAssertTrue(hours.allows(date(day: 19, hour: 17, minute: 59), calendar: calendar))
        XCTAssertFalse(hours.allows(date(day: 19, hour: 18), calendar: calendar))
        XCTAssertFalse(hours.allows(date(day: 19, hour: 8, minute: 59), calendar: calendar))
        // Saturday.
        XCTAssertFalse(hours.allows(date(day: 24, hour: 12), calendar: calendar))
    }

    func testHoursPastMidnight() {
        // Friday 22:00 to 2:00.
        let hours = IvyNotificationHours(weekdays: [6], start: 22 * 60, end: 2 * 60)
        XCTAssertTrue(hours.allows(date(day: 23, hour: 23), calendar: calendar))
        XCTAssertTrue(hours.allows(date(day: 24, hour: 1), calendar: calendar))
        XCTAssertFalse(hours.allows(date(day: 24, hour: 3), calendar: calendar))
        XCTAssertFalse(hours.allows(date(day: 23, hour: 1), calendar: calendar))
    }

    func testWholeDay() {
        let hours = IvyNotificationHours(weekdays: [1, 7], start: 0, end: 0)
        XCTAssertTrue(hours.allows(date(day: 25, hour: 3), calendar: calendar))
        XCTAssertFalse(hours.allows(date(day: 20, hour: 12), calendar: calendar))
    }

    func testFolderRules() {
        let work = Data([1])
        let friends = Data([2])
        let mondayEvening = date(day: 19, hour: 20)
        let mondayMorning = date(day: 19, hour: 10)
        let workRule = IvyNotificationFocus.FolderRule(folderId: work, hours: .workdays)
        let friendsRule = IvyNotificationFocus.FolderRule(folderId: friends, hours: nil)

        // In no folder: always.
        XCTAssertTrue(IvyNotificationFocus.allows(folders: [], focusFolderIds: nil, now: mondayEvening, calendar: calendar))
        // Only in Work.
        XCTAssertTrue(IvyNotificationFocus.allows(folders: [workRule], focusFolderIds: nil, now: mondayMorning, calendar: calendar))
        XCTAssertFalse(IvyNotificationFocus.allows(folders: [workRule], focusFolderIds: nil, now: mondayEvening, calendar: calendar))
        // Also in Friends, which has no hours.
        XCTAssertTrue(IvyNotificationFocus.allows(folders: [workRule, friendsRule], focusFolderIds: nil, now: mondayEvening, calendar: calendar))
        // A Focus that lets only Friends notify.
        XCTAssertFalse(IvyNotificationFocus.allows(folders: [workRule], focusFolderIds: [friends], now: mondayMorning, calendar: calendar))
        XCTAssertFalse(IvyNotificationFocus.allows(folders: [], focusFolderIds: [friends], now: mondayMorning, calendar: calendar))
        XCTAssertTrue(IvyNotificationFocus.allows(folders: [friendsRule], focusFolderIds: [friends], now: mondayEvening, calendar: calendar))
    }

    func testHoursSyncWithFolderExtras() throws {
        let store = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let folderId = Data([7])
        var extras = ChatFolderExtras()
        extras.notificationHours = .workdays
        extras.save(folderId: folderId, comparedTo: ChatFolderExtras(), store: store)
        XCTAssertEqual(ChatFolderExtras.fetch(folderId: folderId, store: store).notificationHours, .workdays)

        var cleared = extras
        cleared.notificationHours = nil
        cleared.save(folderId: folderId, comparedTo: extras, store: store)
        XCTAssertNil(ChatFolderExtras.fetch(folderId: folderId, store: store).notificationHours)
    }

    func testQuietSummaryTime() {
        let next = IvyQuietSummary.nextDate(minutes: 18 * 60, after: date(day: 19, hour: 10), calendar: calendar)
        XCTAssertEqual(next, date(day: 19, hour: 18))
        let tomorrow = IvyQuietSummary.nextDate(minutes: 18 * 60, after: date(day: 19, hour: 19), calendar: calendar)
        XCTAssertEqual(tomorrow, date(day: 20, hour: 18))
    }
}
