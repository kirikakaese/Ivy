//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import XCTest

final class IvyAppearanceTest: XCTestCase {

    func testTheAccentFollowsTheAppIcon() {
        XCTAssertEqual(IvyAppearance.accent(forAppIcon: nil), .ivy)
        XCTAssertEqual(IvyAppearance.accent(forAppIcon: "AppIcon"), .ivy)
        XCTAssertEqual(IvyAppearance.accent(forAppIcon: "AppIcon-ivy-autumn"), .orange)
        XCTAssertEqual(IvyAppearance.accent(forAppIcon: "AppIcon-ivy-trans"), .pink)
        XCTAssertEqual(IvyAppearance.accent(forAppIcon: "AppIcon-ivy-glass"), .petrol)
    }

    func testEveryAccentHasItsOwnColour() {
        let colors = Set(IvyAppearance.Accent.allCases.filter { $0 != .icon }.map { $0.swatch.description })
        XCTAssertEqual(colors.count, IvyAppearance.Accent.allCases.count - 1)
    }
}
