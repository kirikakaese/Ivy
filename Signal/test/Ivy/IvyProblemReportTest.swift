//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

final class IvyProblemReportTest: XCTestCase {

    func testTitleIsFirstLine() {
        XCTAssertEqual(
            IvyProblemReport.title(from: "  Reactions don't send\nTapped twice, nothing.", fallback: "Report"),
            "Reactions don't send",
        )
    }

    func testEmptyDescriptionUsesFallback() {
        XCTAssertEqual(IvyProblemReport.title(from: " \n\n", fallback: "Report"), "Report")
    }

    func testLongTitleIsShortened() {
        let title = IvyProblemReport.title(from: String(repeating: "a", count: 120), fallback: "Report")
        XCTAssertEqual(title.count, 70)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testBodyHasDescriptionHintsAndDetails() {
        let body = IvyProblemReport.body(
            description: "It crashed.\n",
            hints: ["Screenshot: paste it here."],
            details: "Ivy 8.32.0.1910 · iOS 26.1 · iPhone",
        )
        XCTAssertEqual(body, "It crashed.\n\nScreenshot: paste it here.\n\n---\nIvy 8.32.0.1910 · iOS 26.1 · iPhone")
    }

    func testIssueURLKeepsPlusSigns() throws {
        let url = try XCTUnwrap(IvyProblemReport.issueURL(title: "C++ crash", body: "1 + 1"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/kirikakaese/Ivy/issues/new?"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "title" }?.value, "C++ crash")
        XCTAssertEqual(components.queryItems?.first { $0.name == "body" }?.value, "1 + 1")
    }
}
