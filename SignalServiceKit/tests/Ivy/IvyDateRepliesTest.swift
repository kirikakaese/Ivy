//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyDateRepliesTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    /// A moment before the dates used below.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2099, month: 11, day: 1, hour: 10))!
    }

    // NSDataDetector reads absolute dates the same whatever today is, so the
    // tests use a fixed year and pass "now" explicitly.
    private let text = "Shall we meet on 14 November 2099 at 18:00 at the office?"

    func testFindsUpcomingDateInRecentMessage() throws {
        let detected = try XCTUnwrap(IvyDateReplies.date(in: text, messageDate: now.addingTimeInterval(-3600), now: now, calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: detected.date)
        XCTAssertEqual(parts.year, 2099)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 14)
        XCTAssertEqual(parts.hour, 18)
        XCTAssertFalse(detected.isAllDay)
    }

    func testIgnoresOldMessages() {
        let old = now.addingTimeInterval(-3 * 24 * 60 * 60)
        XCTAssertNil(IvyDateReplies.date(in: text, messageDate: old, now: now, calendar: calendar))
    }

    func testIgnoresPastAndFarDates() {
        let later = calendar.date(from: DateComponents(year: 2099, month: 11, day: 20))!
        XCTAssertNil(IvyDateReplies.date(in: text, messageDate: later, now: later, calendar: calendar))
        let longBefore = calendar.date(from: DateComponents(year: 2099, month: 1, day: 1))!
        XCTAssertNil(IvyDateReplies.date(in: text, messageDate: longBefore, now: longBefore, calendar: calendar))
    }

    func testIgnoresMessagesWithoutDates() {
        XCTAssertNil(IvyDateReplies.date(in: "Who is coming along?", messageDate: now, now: now, calendar: calendar))
    }

    func testRecordsAnswersAndDropsTheOldest() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyDateRepliesTest"))
        defaults.removePersistentDomain(forName: "IvyDateRepliesTest")
        defer { defaults.removePersistentDomain(forName: "IvyDateRepliesTest") }

        XCTAssertNil(IvyDateReplies.answer(forMessage: "a", defaults: defaults))
        IvyDateReplies.record(.accept, forMessage: "a", now: now, defaults: defaults)
        IvyDateReplies.record(.decline, forMessage: "b", now: now.addingTimeInterval(1), defaults: defaults)
        XCTAssertEqual(IvyDateReplies.answer(forMessage: "a", defaults: defaults), .accept)
        XCTAssertEqual(IvyDateReplies.answer(forMessage: "b", defaults: defaults), .decline)

        for index in 0..<IvyDateReplies.maximumAnswers {
            IvyDateReplies.record(.accept, forMessage: "m\(index)", now: now.addingTimeInterval(Double(10 + index)), defaults: defaults)
        }
        XCTAssertNil(IvyDateReplies.answer(forMessage: "a", defaults: defaults))
        XCTAssertNil(IvyDateReplies.answer(forMessage: "b", defaults: defaults))
        XCTAssertEqual(IvyDateReplies.answer(forMessage: "m0", defaults: defaults), .accept)
    }
}
