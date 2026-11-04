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

    func testBesideTheMenuOnTheSideOfTheHand() throws {
        let defaults = try freshDefaults()
        XCTAssertEqual(IvyHand.current(defaults: defaults), .right)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .right)
        IvyHand.set(.left, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .left)
        IvyReactionBarPosition.setBesideMenu(false, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .bottom)
        IvyReactionBarPosition.setBesideMenu(true, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .left)
    }

    func testAnEarlierLeftBarMeansTheLeftHand() throws {
        let defaults = try freshDefaults()
        defaults.set("left", forKey: IvyReactionBarPosition.defaultsKey)
        XCTAssertEqual(IvyHand.current(defaults: defaults), .left)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults), .left)
    }

    func testUprightOnlyBesideTheActions() {
        XCTAssertNil(IvyReactionBarPosition.bottom.verticalSide)
        XCTAssertEqual(IvyReactionBarPosition.right.verticalSide, 1)
        XCTAssertEqual(IvyReactionBarPosition.left.verticalSide, -1)
        XCTAssertNil(IvyReactionBarPosition.placementForContextMenu(isLandscapePhone: true))
    }
}
