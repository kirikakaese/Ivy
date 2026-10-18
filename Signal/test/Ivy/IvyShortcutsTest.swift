//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

@MainActor
final class IvyShortcutsTest: XCTestCase {

    func testTodaySummary() throws {
        guard #available(iOS 17, *) else {
            throw XCTSkip("Shortcuts need iOS 17")
        }
        XCTAssertFalse(IvyShortcuts.todaySummary([]).isEmpty)

        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let items = [
            IvyGlance.Item(id: "1", kind: .event, title: "Lunch", start: start, end: start, isAllDay: false, link: IvyLink.event(id: "1").url),
            IvyGlance.Item(id: "2", kind: .task, title: "Taxes", start: start, end: start, isAllDay: true, link: IvyLink.task(id: "2").url),
        ]
        let summary = IvyShortcuts.todaySummary(items)
        XCTAssertTrue(summary.contains("Lunch"))
        XCTAssertTrue(summary.contains("Taxes"))
        XCTAssertTrue(summary.contains(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short)))
    }

    func testSectionsOpenTheirLinks() throws {
        guard #available(iOS 17, *) else {
            throw XCTSkip("Shortcuts need iOS 17")
        }
        XCTAssertEqual(IvyShortcutSection.allCases.map(\.link), [.home, .chats, .calendar, .calls, .tasks])
    }

    func testKeyCommandsDontRepeat() {
        let commands = IvyKeyCommands.commands()
        XCTAssertEqual(commands.count, 6)
        let keys = commands.map { "\($0.modifierFlags.rawValue)-\($0.input ?? "")" }
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(IvyKeyCommands.sectionCommands().map(\.input), ["1", "2", "3", "4"])
    }
}
