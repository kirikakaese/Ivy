//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyFirstTimeTipsTest: XCTestCase {

    private func freshDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyFirstTimeTipsTest"))
        defaults.removePersistentDomain(forName: "IvyFirstTimeTipsTest")
        return defaults
    }

    func testWelcomeAndHintOnce() throws {
        let defaults = try freshDefaults()
        XCTAssertTrue(IvyFirstTimeTips.isWelcomeDue(defaults: defaults))
        IvyFirstTimeTips.markWelcomeShown(defaults: defaults)
        XCTAssertFalse(IvyFirstTimeTips.isWelcomeDue(defaults: defaults))
        XCTAssertTrue(IvyFirstTimeTips.takeSheetHint(defaults: defaults))
        XCTAssertFalse(IvyFirstTimeTips.takeSheetHint(defaults: defaults))
    }

    func testBarTipThreeTimesOrUntilClosed() throws {
        let defaults = try freshDefaults()
        XCTAssertEqual((0..<5).map { _ in IvyFirstTimeTips.takeBarTip(defaults: defaults, appliesHere: true) }, [true, true, true, false, false])
        IvyFirstTimeTips.reset(defaults: defaults)
        XCTAssertTrue(IvyFirstTimeTips.takeBarTip(defaults: defaults, appliesHere: true))
        IvyFirstTimeTips.closeBarTip(defaults: defaults)
        XCTAssertFalse(IvyFirstTimeTips.takeBarTip(defaults: defaults, appliesHere: true))
        XCTAssertTrue(IvyFirstTimeTips.isWelcomeDue(defaults: defaults))
    }
}
