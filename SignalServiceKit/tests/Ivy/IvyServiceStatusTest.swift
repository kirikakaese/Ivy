//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyServiceStatusTest: XCTestCase {

    private func status(_ json: String) throws -> IvyServiceStatus? {
        let report = try JSONDecoder().decode(IvyServiceStatus.Report.self, from: Data(json.utf8))
        return IvyServiceStatus.from(report)
    }

    func testAllWell() throws {
        XCTAssertNil(try status(#"{"status":"ok","components":[{"name":"Ivy Push relay","status":"ok"}],"active":[]}"#))
        XCTAssertNil(try status(#"{"status":"unknown","components":[],"active":[]}"#))
    }

    func testAutomaticProblemNamesAffectedServices() throws {
        let result = try XCTUnwrap(status(#"""
        {"status":"degraded","components":[
          {"name":"Ivy Push relay","status":"ok"},
          {"name":"Apple push delivery","status":"degraded"},
          {"name":"Signal service","status":"unknown"}
        ],"active":[]}
        """#))
        XCTAssertEqual(result.level, .degraded)
        XCTAssertNil(result.title)
        XCTAssertEqual(result.components, ["Apple push delivery"])
        XCTAssertTrue(result.isProblem)
    }

    func testIncidentComesFirst() throws {
        let result = try XCTUnwrap(status(#"""
        {"status":"degraded","components":[],"active":[
          {"id":"n1","kind":"notice","title":"New version","components":[]},
          {"id":"i1","kind":"incident","title":"Relay unreachable","impact":"major","components":["Ivy Push relay"],
           "updates":[{"time":"2026-10-29T10:00:00Z","step":"investigating","message":"Looking into it."},
                      {"time":"2026-10-29T10:20:00Z","step":"identified","message":" Server is back after a billing issue. "}]}
        ]}
        """#))
        XCTAssertEqual(result.level, .down)
        XCTAssertEqual(result.title, "Relay unreachable")
        XCTAssertEqual(result.detail, "Server is back after a billing issue.")
        XCTAssertEqual(result.components, ["Ivy Push relay"])
        XCTAssertEqual(result.id, "post.i1")
    }

    func testMinorIncidentIsDegraded() throws {
        let result = try XCTUnwrap(status(#"{"status":"ok","active":[{"id":"i2","kind":"incident","title":"Slow","impact":"minor","components":null}]}"#))
        XCTAssertEqual(result.level, .degraded)
        XCTAssertEqual(result.components, [])
        XCTAssertNil(result.detail)
    }

    func testMaintenanceAndNotice() throws {
        let maintenance = try XCTUnwrap(status(#"{"status":"maintenance","active":[{"id":"m1","kind":"maintenance","title":"Server update","components":["Ivy Push relay"]}]}"#))
        XCTAssertEqual(maintenance.level, .maintenance)
        XCTAssertEqual(maintenance.title, "Server update")

        let notice = try XCTUnwrap(status(#"{"status":"ok","active":[{"id":"n1","kind":"notice","title":"New version","components":[]}]}"#))
        XCTAssertEqual(notice.level, .notice)
        XCTAssertFalse(notice.isProblem)
    }

    func testOutageOutranksMaintenancePost() throws {
        let result = try XCTUnwrap(status(#"{"status":"down","components":[{"name":"Signal service","status":"down"}],"active":[{"id":"m1","kind":"maintenance","title":"Server update","components":[]}]}"#))
        XCTAssertEqual(result.level, .down)
        XCTAssertEqual(result.id, "status.down")
    }

    func testReportAddress() {
        XCTAssertEqual(
            IvyServiceStatus.reportURL(for: URL(string: "https://relay.example.com")!).absoluteString,
            "https://relay.example.com/status/status.json",
        )
    }
}
