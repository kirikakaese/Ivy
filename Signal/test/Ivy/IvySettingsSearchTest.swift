//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvySettingsSearchTest: XCTestCase {

    private func entry(_ title: String, _ place: String? = nil) -> IvySettingsEntry {
        IvySettingsEntry(title: title, place: place) { _ in }
    }

    func testFindsByNameAndPageIgnoringCaseAndAccents() {
        let entries = [entry("Doppeltippen", "Bedienung"), entry("Hand", "Bedienung"), entry("Datenschutz"), entry("Mitteilungen")]
        XCTAssertEqual(IvySettingsIndex.matches(entries, query: "doppel").map(\.title), ["Doppeltippen"])
        XCTAssertEqual(IvySettingsIndex.matches(entries, query: "bedienung").map(\.title), ["Doppeltippen", "Hand"])
        XCTAssertEqual(IvySettingsIndex.matches([entry("Ivy-Sync und Sicherung")], query: "sicherung SYNC").count, 1)
        XCTAssertTrue(IvySettingsIndex.matches(entries, query: "  ").isEmpty)
    }

    func testNamesThatStartWithTheQueryComeFirst() {
        let entries = [entry("Tipps erneut zeigen", "Bedienung"), entry("Doppeltippen", "Bedienung")]
        XCTAssertEqual(IvySettingsIndex.matches(entries, query: "tipp").map(\.title), ["Tipps erneut zeigen", "Doppeltippen"])
    }

    func testEveryIvyPageHasANameAndAnIcon() {
        for page in IvySettingsPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertNotNil(UIImage(systemName: page.symbol), page.symbol)
        }
    }
}
