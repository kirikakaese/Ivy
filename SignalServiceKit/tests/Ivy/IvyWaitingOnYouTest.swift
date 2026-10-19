//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyWaitingOnYouTest: XCTestCase {

    func testQuestions() {
        XCTAssertTrue(IvyWaitingOnYou.isQuestion("Are you coming tonight?"))
        XCTAssertTrue(IvyWaitingOnYou.isQuestion("Kommst du? 🙂"))
        XCTAssertTrue(IvyWaitingOnYou.isQuestion("¿Vienes"))
        XCTAssertTrue(IvyWaitingOnYou.isQuestion("明天见？"))
        XCTAssertFalse(IvyWaitingOnYou.isQuestion("See you tonight."))
        XCTAssertFalse(IvyWaitingOnYou.isQuestion("Look: https://example.com/page?id=4"))
        XCTAssertTrue(IvyWaitingOnYou.isQuestion("Seen this? https://example.com/page?id=4"))
    }

    func testWhichQuestionsCount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-3600)
        let old = now.addingTimeInterval(-IvyWaitingOnYou.maxAge - 1)

        XCTAssertTrue(IvyWaitingOnYou.counts(isGroup: false, mentionsUser: false, repliesToUser: false, text: "Lunch?", sentAt: recent, now: now))
        XCTAssertFalse(IvyWaitingOnYou.counts(isGroup: false, mentionsUser: false, repliesToUser: false, text: "Lunch?", sentAt: old, now: now))
        XCTAssertFalse(IvyWaitingOnYou.counts(isGroup: false, mentionsUser: false, repliesToUser: false, text: "Lunch.", sentAt: recent, now: now))

        XCTAssertFalse(IvyWaitingOnYou.counts(isGroup: true, mentionsUser: false, repliesToUser: false, text: "Lunch?", sentAt: recent, now: now))
        XCTAssertTrue(IvyWaitingOnYou.counts(isGroup: true, mentionsUser: true, repliesToUser: false, text: "Lunch?", sentAt: recent, now: now))
        XCTAssertTrue(IvyWaitingOnYou.counts(isGroup: true, mentionsUser: false, repliesToUser: true, text: "Lunch?", sentAt: recent, now: now))
    }
}
