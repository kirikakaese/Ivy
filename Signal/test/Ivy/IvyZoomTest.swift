//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import XCTest

@testable import Signal

final class IvyZoomTest: XCTestCase {

    func testSizesGrowFromTheSystemDefault() {
        XCTAssertEqual(IvyZoom.sizes[IvyZoom.defaultIndex], .large)
        let order: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
            .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        ]
        let positions = IvyZoom.sizes.compactMap { order.firstIndex(of: $0) }
        XCTAssertEqual(positions.count, IvyZoom.sizes.count)
        XCTAssertEqual(positions, positions.sorted())
    }
}
