//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyQuickReactionsBarTest: XCTestCase {

    func testOffersTheReactionsThereAndMarksYours() {
        let choices = IvyQuickReactionsBar.choices(emojis: ["👍", "❤️"], yours: "❤️")
        XCTAssertEqual(choices, [
            .init(emoji: "👍", isYours: false),
            .init(emoji: "❤️", isYours: true),
        ])
    }

    func testWithoutYourReactionAllJoinIn() {
        let choices = IvyQuickReactionsBar.choices(emojis: ["😂"], yours: nil)
        XCTAssertEqual(choices.map(\.isYours), [false])
        XCTAssertTrue(IvyQuickReactionsBar.choices(emojis: [], yours: nil).isEmpty)
    }
}
