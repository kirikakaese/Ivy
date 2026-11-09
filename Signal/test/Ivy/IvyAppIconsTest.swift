//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyAppIconsTest: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(month: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!
    }

    func testJuneShowsTheRainbowWhenAskedFor() {
        XCTAssertEqual(IvyAppIcons.effectiveIcon(chosen: .mint, prideInJune: true, now: date(month: 6), calendar: calendar), .rainbow)
        XCTAssertEqual(IvyAppIcons.effectiveIcon(chosen: .mint, prideInJune: true, now: date(month: 7), calendar: calendar), .mint)
        XCTAssertEqual(IvyAppIcons.effectiveIcon(chosen: .mint, prideInJune: false, now: date(month: 6), calendar: calendar), .mint)
    }

    func testAChosenPrideIconStaysInJune() {
        XCTAssertEqual(IvyAppIcons.effectiveIcon(chosen: .trans, prideInJune: true, now: date(month: 6), calendar: calendar), .trans)
    }

    func testEveryIconHasAGroupAndAName() {
        XCTAssertEqual(IvyAppIcon.icons(in: .ivy).count, 5)
        XCTAssertEqual(IvyAppIcon.icons(in: .pride).count, 7)
        XCTAssertEqual(IvyAppIcon.icons(in: .classic).count, 4)
        XCTAssertNil(IvyAppIcon.dark.alternateIconName)
        XCTAssertEqual(IvyAppIcon(alternateIconName: "AppIcon-ivy-pan"), .pan)
        XCTAssertEqual(IvyAppIcon(alternateIconName: nil), .dark)
        XCTAssertEqual(IvyAppIcon(alternateIconName: "AppIcon-news"), .dark)
    }
}
