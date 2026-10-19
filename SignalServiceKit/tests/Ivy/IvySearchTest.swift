//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class IvySearchTest: XCTestCase {

    func testWordsMatchInAnyOrder() {
        XCTAssertTrue(IvySearch.contains("rent pay", in: ["Pay the rent"]))
        XCTAssertTrue(IvySearch.contains("cafe", in: ["Meet at the Café"]))
        XCTAssertTrue(IvySearch.contains("berlin", in: ["Trip", "Berlin, Germany"]))
        XCTAssertFalse(IvySearch.contains("rent car", in: ["Pay the rent"]))
        XCTAssertFalse(IvySearch.contains("   ", in: ["Anything"]))
    }

    func testLinksInText() {
        let links = IvyLibrary.links(in: "Look at https://example.com/a?b=1 and http://example.org, not ftp://x.y or mail@example.com")
        XCTAssertEqual(links.map(\.absoluteString), ["https://example.com/a?b=1", "http://example.org"])
        XCTAssertTrue(IvyLibrary.links(in: "No links here").isEmpty)
    }

    func testFiltersThatOnlyFitMessages() {
        XCTAssertFalse(IvySearchFilter().limitsToMessages)
        XCTAssertFalse(IvySearchFilter(since: Date()).limitsToMessages)
        XCTAssertTrue(IvySearchFilter(content: .link).limitsToMessages)
        XCTAssertTrue(IvySearchFilter(author: Aci(fromUUID: UUID())).limitsToMessages)
    }
}
