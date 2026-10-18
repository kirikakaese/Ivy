//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyZoomTest: XCTestCase {

    func testSizesGrowFromTheSystemDefault() {
        XCTAssertEqual(IvyZoom.sizes[IvyZoom.defaultIndex], .large)
        for (smaller, larger) in zip(IvyZoom.sizes, IvyZoom.sizes.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
    }
}
