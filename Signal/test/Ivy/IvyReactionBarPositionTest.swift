//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyReactionBarPositionTest: XCTestCase {

    private func freshDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyReactionBarPositionTest"))
        defaults.removePersistentDomain(forName: "IvyReactionBarPositionTest")
        return defaults
    }

    func testRightUntilChosenAndKeptOnceChosen() throws {
        let defaults = try freshDefaults()
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .right)
        IvyReactionBarPosition.set(.left, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .left)
        defaults.set("sideways", forKey: IvyReactionBarPosition.defaultsKey)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .right)
    }

    func testUprightOnlyBesideTheActions() {
        XCTAssertNil(IvyReactionBarPosition.bottom.verticalSide)
        XCTAssertEqual(IvyReactionBarPosition.right.verticalSide, 1)
        XCTAssertEqual(IvyReactionBarPosition.left.verticalSide, -1)
        XCTAssertNil(IvyReactionBarPosition.placementForContextMenu(isLandscapePhone: true))
    }
}
