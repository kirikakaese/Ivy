//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyWakeStatsTest: XCTestCase {

    func testCountsTheLastSevenDays() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyWakeStatsTest"))
        defaults.removePersistentDomain(forName: "IvyWakeStatsTest")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let eightDaysAgo = calendar.date(byAdding: .day, value: -8, to: now)!
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!

        IvyWakeStats.record(.empty, now: eightDaysAgo, calendar: calendar, defaults: defaults)
        IvyWakeStats.record(.message, now: sixDaysAgo, calendar: calendar, defaults: defaults)
        IvyWakeStats.record(.message, now: now, calendar: calendar, defaults: defaults)
        IvyWakeStats.record(.empty, now: now, calendar: calendar, defaults: defaults)
        IvyWakeStats.record(.alreadyShown, now: now, calendar: calendar, defaults: defaults)

        let totals = IvyWakeStats.lastWeek(now: now, calendar: calendar, defaults: defaults)
        XCTAssertEqual(totals[.message], 2)
        XCTAssertEqual(totals[.empty], 1, "eight days ago is left out")
        XCTAssertEqual(totals[.alreadyShown], 1)
        XCTAssertEqual((defaults.dictionary(forKey: "IvyWakeStats") ?? [:]).count, 2, "older days are dropped")
    }
}
