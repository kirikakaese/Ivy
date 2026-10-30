//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyStatusReportTest: XCTestCase {

    /// As the gateway writes it, with nanoseconds and fields the app doesn't use.
    private let json = #"""
    {"status":"degraded","message":"Some parts are slow.","checked":"2026-10-29T16:32:11.985314185Z",
     "components":[{"id":"relay","name":"Ivy Push relay","description":"Wakes Ivy.","status":"down",
       "days":[{"date":"2026-10-28","status":"none"},
               {"date":"2026-10-29","status":"down","minutes":{"ok":900,"maintenance":0,"degraded":40,"down":125},
                "hours":[{"hour":12,"down":35},{"hour":14,"down":30,"degraded":30}]}]},
       {"id":"signal","name":"Signal service","description":"Answers.","status":"ok","detail":"reachable, 180 ms","days":[]}],
     "metrics":{"uptime30":99.62,"uptime90":99.81,"wakeMedianMs":212,"acceptance24h":null},
     "active":[{"id":"i1","kind":"incident","title":"Relay unreachable","impact":"major","components":["Ivy Push relay"],
       "created":"2026-10-29T12:25:00Z","updates":[{"time":"2026-10-29T12:25:00.5Z","step":"investigating","message":""}]}],
     "upcoming":[],"recent":[],"days":[],"marked":[]}
    """#

    func testDecodesTheGatewaysReport() throws {
        let report = try IvyStatusReport.decode(Data(json.utf8))
        XCTAssertEqual(report.status, "degraded")
        XCTAssertEqual(report.checked, IvyStatusReport.parseDate("2026-10-29T16:32:11Z"))
        XCTAssertEqual(report.components.map(\.id), ["relay", "signal"])
        let day = try XCTUnwrap(report.components[0].days?.last)
        XCTAssertEqual(day.minutes?.total, 1065)
        XCTAssertEqual(day.hours?.last?.degraded, 30)
        XCTAssertNil(report.components[0].days?.first?.minutes)
        XCTAssertEqual(report.metrics?.wakeMedianMs, 212)
        XCTAssertNil(report.metrics?.acceptance24h)
        XCTAssertEqual(report.active?.first?.updates?.first?.step, "investigating")
    }

    func testDatesWithAndWithoutFractions() {
        XCTAssertNotNil(IvyStatusReport.parseDate("2026-10-29T16:32:11Z"))
        XCTAssertEqual(IvyStatusReport.parseDate("2026-10-29T16:32:11.985314185Z"), IvyStatusReport.parseDate("2026-10-29T16:32:11Z"))
        XCTAssertNil(IvyStatusReport.parseDate("yesterday"))
    }

    func testTheLastReportIsKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyStatusReportTest"))
        defaults.removePersistentDomain(forName: "IvyStatusReportTest")
        XCTAssertNil(IvyStatusReport.Saved.load(defaults: defaults))
        let received = Date(timeIntervalSince1970: 1_800_000_000)
        IvyStatusReport.Saved.store(Data(json.utf8), at: received, defaults: defaults)
        let saved = try XCTUnwrap(IvyStatusReport.Saved.load(defaults: defaults))
        XCTAssertEqual(saved.received, received)
        XCTAssertEqual(saved.report.components.count, 2)
    }
}
