//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyDoubleTapReactionTest: XCTestCase {

    func testReactsOrTakesBack() {
        XCTAssertEqual(IvyDoubleTapReaction.action(emoji: "❤️", yourReaction: nil).isRemoving, false)
        XCTAssertEqual(IvyDoubleTapReaction.action(emoji: "❤️", yourReaction: "👍").emoji, "❤️")
        XCTAssertEqual(IvyDoubleTapReaction.action(emoji: "❤️", yourReaction: "👍").isRemoving, false)
        XCTAssertEqual(IvyDoubleTapReaction.action(emoji: "❤️", yourReaction: "❤️").isRemoving, true)
    }

    func testOnWithAHeartUntilChanged() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IvyDoubleTapReactionTest"))
        defaults.removePersistentDomain(forName: "IvyDoubleTapReactionTest")
        XCTAssertTrue(IvyDoubleTapReaction.isEnabled(defaults: defaults))
        XCTAssertEqual(IvyDoubleTapReaction.emoji(defaults: defaults), "❤️")
        IvyDoubleTapReaction.setEnabled(false, defaults: defaults)
        IvyDoubleTapReaction.setEmoji("😂", defaults: defaults)
        XCTAssertFalse(IvyDoubleTapReaction.isEnabled(defaults: defaults))
        XCTAssertEqual(IvyDoubleTapReaction.emoji(defaults: defaults), "😂")
    }
}
