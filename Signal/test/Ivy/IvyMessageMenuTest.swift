//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyMessageMenuTest: XCTestCase {

    private let defaultMore = IvyMessageMenuItem.underMoreByDefault

    func testEverydayActionsBecomeIconsAndTheRestSplits() {
        let items: [IvyMessageMenuItem] = [.reply, .forward, .copy, .select, .info, .pin, .star, .remind, .task, .calendar, .delete]
        let plan = IvyMessageMenu.plan(items: items, underMore: defaultMore)
        XCTAssertEqual(plan.icons.map { items[$0] }, [.reply, .copy, .forward, .select])
        XCTAssertEqual(plan.rows.map { items[$0] }, [.info, .pin, .star])
        XCTAssertEqual(plan.more.map { items[$0] }, [.remind, .task, .calendar])
        XCTAssertEqual(plan.delete.map { items[$0] }, [.delete])
    }

    func testOneActionUnderMoreStaysARow() {
        let items: [IvyMessageMenuItem] = [.reply, .copy, .info, .remind, .delete]
        let plan = IvyMessageMenu.plan(items: items, underMore: defaultMore)
        XCTAssertTrue(plan.more.isEmpty)
        XCTAssertEqual(plan.rows.map { items[$0] }, [.info, .remind])
    }

    func testAnIconRowNeedsTwoActions() {
        let items: [IvyMessageMenuItem] = [.reply, .info, .delete]
        let plan = IvyMessageMenu.plan(items: items, underMore: [])
        XCTAssertTrue(plan.icons.isEmpty)
        XCTAssertEqual(plan.rows.map { items[$0] }, [.reply, .info])
    }

    func testChoicesAreKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyMessageMenuTest"))
        defaults.removePersistentDomain(forName: "IvyMessageMenuTest")
        XCTAssertEqual(IvyMessageMenu.underMore(defaults: defaults), defaultMore)
        IvyMessageMenu.setShownDirectly(.remind, true, defaults: defaults)
        IvyMessageMenu.setShownDirectly(.info, false, defaults: defaults)
        let saved = IvyMessageMenu.underMore(defaults: defaults)
        XCTAssertFalse(saved.contains(.remind))
        XCTAssertTrue(saved.contains(.info))
    }
}
