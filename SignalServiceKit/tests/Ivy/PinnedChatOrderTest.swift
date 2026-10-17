//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class PinnedChatOrderTest: XCTestCase {

    func testRearrangingVisibleChatsKeepsHiddenOnesInPlace() {
        let order = PinnedChatOrder.order(all: ["a", "b", "c", "d"], visibleInNewOrder: ["d", "b"])
        XCTAssertEqual(order, ["a", "d", "c", "b"])
    }

    func testRearrangingAllChats() {
        let order = PinnedChatOrder.order(all: ["a", "b", "c"], visibleInNewOrder: ["c", "a", "b"])
        XCTAssertEqual(order, ["c", "a", "b"])
    }

    func testMoveUpAndDown() {
        XCTAssertEqual(PinnedChatOrder.order(all: ["a", "b", "c"], moving: "c", by: -1), ["a", "c", "b"])
        XCTAssertEqual(PinnedChatOrder.order(all: ["a", "b", "c"], moving: "a", by: 1), ["b", "a", "c"])
        XCTAssertEqual(PinnedChatOrder.order(all: ["a", "b", "c"], moving: "a", by: -1), ["a", "b", "c"])
        XCTAssertEqual(PinnedChatOrder.order(all: ["a", "b", "c"], moving: "x", by: 1), ["a", "b", "c"])
    }
}
