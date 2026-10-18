//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class IvyTaskUITest: XCTestCase {

    func testPriorityMarker() {
        XCTAssertNil(IvyTaskUI.marker(for: .none))
        XCTAssertEqual(IvyTaskUI.marker(for: .low), "!")
        XCTAssertEqual(IvyTaskUI.marker(for: .high), "!!!")
    }

    func testSubtitle() {
        XCTAssertNil(IvyTaskUI.subtitle(for: IvyTask(title: "a"), listName: nil))

        let task = IvyTask(title: "a", subtasks: [.init(title: "1", isDone: true), .init(title: "2"), .init(title: "3")])
        XCTAssertEqual(IvyTaskUI.subtitle(for: task, listName: "Work"), "Work · 1/3")

        let dated = IvyTask(title: "a", dueAt: Date(), isAllDay: true)
        let subtitle = IvyTaskUI.subtitle(for: dated, listName: nil)
        XCTAssertEqual(subtitle, IvyTaskUI.dueText(for: dated))
        XCTAssertFalse(subtitle?.isEmpty ?? true)
    }

    func testEveryGroupAndPriorityHasATitle() {
        for group in IvyTask.Group.allCases {
            XCTAssertFalse(IvyTaskUI.title(for: group).isEmpty)
        }
        for priority in IvyTask.Priority.allCases {
            XCTAssertFalse(IvyTaskUI.title(for: priority).isEmpty)
        }
    }

    @MainActor
    func testTaskRowShowsTitleAndDetails() {
        let task = IvyTask(title: "Buy milk", listId: "list", priority: .high, subtasks: [.init(title: "1")])
        let row = IvyTaskRowView(task: task, listName: "Shopping", now: Date())
        XCTAssertEqual(row.titleLabel.text, "!!! Buy milk")
        XCTAssertEqual(row.subtitleLabel.text, "Shopping · 0/1")
        XCTAssertFalse(row.subtitleLabel.isHidden)
    }
}
