//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyAboutTest: XCTestCase {

    func testAcknowledgementsAreBundled() {
        let acknowledgements = IvyAcknowledgementsViewController.loadAcknowledgements()
        XCTAssertFalse(acknowledgements.isEmpty)
        XCTAssertTrue(acknowledgements.allSatisfy { !$0.title.isEmpty && !$0.text.isEmpty })
    }
}
