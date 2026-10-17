//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

@MainActor
final class ChatFolderBarTest: XCTestCase {

    private let allChats = ChatFolder(kind: .allChats, name: "")
    private let work = ChatFolder(name: "Work", position: 1)

    private func buttons(in bar: ChatFolderBar) -> [UIButton] {
        var result = [UIButton]()
        var views: [UIView] = [bar]
        while let view = views.popLast() {
            if let button = view as? UIButton {
                result.append(button)
            } else {
                views += view.subviews.reversed()
            }
        }
        return result
    }

    func testShowsAButtonPerFolderAndAnEditButton() {
        let bar = ChatFolderBar(layout: .tabs)
        bar.update(
            items: [.init(folder: allChats, unreadCount: 0), .init(folder: work, unreadCount: 2)],
            selectedFolderId: work.id,
        )
        let buttons = buttons(in: bar)
        XCTAssertEqual(buttons.count, 3)
        XCTAssertEqual(buttons[1].accessibilityLabel, "Work")
        XCTAssertTrue(buttons[1].isSelected)
        XCTAssertFalse(buttons[0].isSelected)
        XCTAssertNotNil(buttons[1].accessibilityValue)
        XCTAssertNil(buttons[0].accessibilityValue)
    }

    func testSelectingAFolder() {
        let bar = ChatFolderBar(layout: .sidebar)
        var selected: ChatFolder?
        bar.onSelect = { selected = $0 }
        bar.update(items: [.init(folder: allChats, unreadCount: 0), .init(folder: work, unreadCount: 0)], selectedFolderId: allChats.id)
        buttons(in: bar)[1].sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(selected?.id, work.id)
    }

    func testLayoutSizes() {
        XCTAssertEqual(ChatFolderBar(layout: .sidebar).intrinsicContentSize.width, ChatFolderBar.sidebarWidth)
        XCTAssertGreaterThan(ChatFolderBar(layout: .tabs).intrinsicContentSize.height, 0)
    }

    func testFolderSummary() {
        let folder = ChatFolder(name: "Mixed", showOnlyUnread: true, includeAllGroupChats: true, includedThreadIds: ["a", "b"])
        let summary = ChatFoldersSettingsViewController.summary(of: folder)
        XCTAssertEqual(summary.components(separatedBy: ", ").count, 3)
        XCTAssertEqual(ChatFoldersSettingsViewController.summary(of: ChatFolder(name: "Empty")), "")
    }
}
