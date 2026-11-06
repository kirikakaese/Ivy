//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyNotificationActionsTest: XCTestCase {

    private let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2099, month: 11, day: 1, hour: 10))!
    }()

    func testMessagesWithADateGetTheDateCategory() {
        XCTAssertEqual(
            IvyNotificationActions.categoryIdentifier(
                signalCategory: "signal",
                canReply: true,
                body: "Shall we meet on 14 November 2099 at 18:00?",
                now: now,
            ),
            IvyNotificationActions.dateCategoryIdentifier,
        )
    }

    func testOtherMessagesKeepSignalsCategory() {
        XCTAssertEqual(
            IvyNotificationActions.categoryIdentifier(signalCategory: "signal", canReply: true, body: "See you!", now: now),
            "signal",
        )
        XCTAssertEqual(
            IvyNotificationActions.categoryIdentifier(
                signalCategory: "signal",
                canReply: false,
                body: "Shall we meet on 14 November 2099 at 18:00?",
                now: now,
            ),
            "signal",
        )
    }

    func testDateCategoryPutsAcceptAndDeclineFirst() throws {
        let message = UNNotificationAction(identifier: "markAsRead", title: "Read", options: [])
        let category = try XCTUnwrap(IvyNotificationActions.categories(messageActions: [message]).first)
        XCTAssertEqual(category.actions.map(\.identifier), [
            IvyNotificationActions.Action.accept.rawValue,
            IvyNotificationActions.Action.decline.rawValue,
            "markAsRead",
        ])
        XCTAssertEqual(IvyNotificationActions.extraMessageActions.map(\.identifier), [
            IvyNotificationActions.Action.heart.rawValue,
            IvyNotificationActions.Action.remindInAnHour.rawValue,
        ])
    }
}
