//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyOneHandTest: XCTestCase {

    private func freshDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyOneHandTest"))
        defaults.removePersistentDomain(forName: "IvyOneHandTest")
        return defaults
    }

    func testSwipeLeftStarsUntilChosen() throws {
        let defaults = try freshDefaults()
        XCTAssertEqual(IvySwipeLeft.current(defaults: defaults), .star)
        IvySwipeLeft.set(.info, defaults: defaults)
        XCTAssertEqual(IvySwipeLeft.current(defaults: defaults), .info)
        defaults.set("sideways", forKey: IvySwipeLeft.defaultsKey)
        XCTAssertEqual(IvySwipeLeft.current(defaults: defaults), .star)
    }

    func testSearchAtTheBottomIsOptIn() throws {
        let defaults = try freshDefaults()
        XCTAssertFalse(IvyChatListLayout.searchAtBottom(defaults: defaults))
        IvyChatListLayout.setSearchAtBottom(true, defaults: defaults)
        XCTAssertTrue(IvyChatListLayout.searchAtBottom(defaults: defaults))
    }
}
