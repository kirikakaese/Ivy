//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

@MainActor
final class IvySidebarTest: XCTestCase {

    func testStateTellsAboutChangesOnce() {
        let state = IvySidebarState()
        var changes = 0
        let observer = NotificationCenter.default.addObserver(forName: IvySidebarState.didChange, object: nil, queue: nil) { _ in
            changes += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let work = ChatFolder(name: "Work", position: 1)
        let items = [ChatFolderBar.Item(folder: work, unreadCount: 3)]
        state.update(folders: items, allChatsFolder: nil, selectedFolderId: work.id)
        state.update(folders: items, allChatsFolder: nil, selectedFolderId: work.id)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(state.selectedFolderId, work.id)

        state.updateBadges(unreadChatCount: 4, unreadCallsCount: 1)
        state.updateBadges(unreadChatCount: 4, unreadCallsCount: 1)
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(state.unreadCallsCount, 1)
    }

    func testEverySectionHasASymbol() {
        for tab in [HomeTabBarController.Tabs.home, .chatList, .calendar, .calls] {
            XCTAssertNotNil(UIImage(systemName: IvySidebarViewController.symbolName(for: tab)), "\(tab)")
        }
    }
}
