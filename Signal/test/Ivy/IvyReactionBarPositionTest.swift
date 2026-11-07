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
        XCTAssertEqual(IvyHand.current(defaults: defaults, appliesHere: true), .right)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults, appliesHere: true), .right)
        IvyHand.set(.left, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults, appliesHere: true), .left)
        IvyReactionBarPosition.setBesideMenu(false, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults, appliesHere: true), .bottom)
        IvyReactionBarPosition.setBesideMenu(true, defaults: defaults)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults, appliesHere: true), .left)
    }

    func testAnEarlierLeftBarMeansTheLeftHand() throws {
        let defaults = try freshDefaults()
        defaults.set("left", forKey: IvyReactionBarPosition.defaultsKey)
        XCTAssertEqual(IvyHand.current(defaults: defaults, appliesHere: true), .left)
        XCTAssertEqual(IvyReactionBarPosition.current(defaults: defaults, appliesHere: true), .left)
    }

    func testUprightOnlyBesideTheActions() {
        XCTAssertNil(IvyReactionBarPosition.bottom.verticalSide)
        XCTAssertEqual(IvyReactionBarPosition.right.verticalSide, 1)
        XCTAssertEqual(IvyReactionBarPosition.left.verticalSide, -1)
        XCTAssertNil(IvyReactionBarPosition.placementForContextMenu(isLandscapePhone: true, appliesHere: true))
    }

    /// On the Mac the one-hand settings don't apply: Signal's layout stays.
    func testTheMacKeepsSignalsLayout() throws {
        let defaults = try freshDefaults()
        IvyHand.set(.left, defaults: defaults)
        defaults.set(true, forKey: IvyChatListLayout.searchAtBottomKey)
        defaults.set(IvySwipeLeft.copy.rawValue, forKey: IvySwipeLeft.defaultsKey)
        XCTAssertEqual(IvyHand.current(defaults: defaults, appliesHere: false), .right)
        XCTAssertNil(IvyReactionBarPosition.placementForContextMenu(isLandscapePhone: false, appliesHere: false))
        XCTAssertFalse(IvyChatListLayout.searchAtBottom(defaults: defaults, appliesHere: false))
        XCTAssertEqual(IvySwipeLeft.current(defaults: defaults, appliesHere: false), .info)
        XCTAssertFalse(IvyFirstTimeTips.takeBarTip(defaults: defaults, appliesHere: false))
    }
}
