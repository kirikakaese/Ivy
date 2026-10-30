//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class IvyStatusScreenTest: XCTestCase {

    /// A report with one relay day per entry, as the gateway sends it.
    private func report(days: [String] = []) throws -> IvyStatusReport {
        let json = #"{"status":"ok","components":[{"id":"relay","name":"Ivy Push relay","description":"","status":"ok","days":["# + days.joined(separator: ",") + "]}]}"
        return try IvyStatusReport.decode(Data(json.utf8))
    }

    private func day(_ status: String, ok: Int = 0, degraded: Int = 0, down: Int = 0) throws -> IvyStatusReport.Day {
        let json = #"{"date":"2026-10-29","status":"\#(status)","minutes":{"ok":\#(ok),"maintenance":0,"degraded":\#(degraded),"down":\#(down)}}"#
        return try XCTUnwrap(report(days: [json]).components.first?.days?.first)
    }

    private func emptyDay() throws -> IvyStatusReport.Day {
        try XCTUnwrap(report(days: [#"{"date":"2026-10-28","status":"none"}"#]).components.first?.days?.first)
    }

    @MainActor
    func testBarsGlowFromTheTopForPartOfADay() throws {
        XCTAssertEqual(IvyStatusDayBars.gradient(for: try day("ok", ok: 1440)).locations, [0, 1])
        XCTAssertEqual(IvyStatusDayBars.gradient(for: try day("down", down: 1440)).locations, [0, 1], "a whole day down is filled")
        let partial = IvyStatusDayBars.gradient(for: try day("down", ok: 1300, down: 140))
        XCTAssertEqual(partial.locations.count, 3)
        XCTAssertGreaterThan(partial.locations[1], 0)
        XCTAssertLessThan(partial.locations[1], 1)
        XCTAssertEqual(IvyStatusDayBars.gradient(for: try emptyDay()).locations, [0, 1])
    }

    func testDaySummaryAndUptime() throws {
        XCTAssertEqual(IvyStatusTexts.daySummary(try day("ok", ok: 1440)), IvyLocalizedString("STATUS_DAY_ALL_WORKING", comment: ""))
        XCTAssertEqual(IvyStatusTexts.daySummary(try emptyDay()), IvyLocalizedString("STATUS_DAY_NO_DATA", comment: ""))
        let summary = IvyStatusTexts.daySummary(try day("down", ok: 1300, degraded: 20, down: 120))
        XCTAssertEqual(summary.components(separatedBy: " · ").count, 3)
        XCTAssertEqual(IvyStatusTexts.uptime([try day("ok", ok: 90), try day("down", down: 10)]), 90)
        XCTAssertNil(IvyStatusTexts.uptime([]))
    }

    func testKnownServicesAreNamedInIvysWords() throws {
        XCTAssertEqual(IvyStatusTexts.names(["Ivy Push relay", "Other"], report: try report()), [IvyLocalizedString("STATUS_SERVICE_RELAY", comment: ""), "Other"])
        XCTAssertEqual(IvyStatusTexts.tone(for: "down"), .red)
        XCTAssertNil(IvyStatusTexts.tone(for: "unknown"))
    }
}
