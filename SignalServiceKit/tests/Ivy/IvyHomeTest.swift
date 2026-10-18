//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyHomeTest: SSKBaseTest {

    func testStartSectionDefaultsToChats() {
        read { tx in
            XCTAssertEqual(IvyHomeSettings.startSection(tx: tx), .chats)
        }
        write { tx in
            IvyHomeSettings.setStartSection(.home, tx: tx)
        }
        read { tx in
            XCTAssertEqual(IvyHomeSettings.startSection(tx: tx), .home)
        }
    }

    func testImportantChatsRoundTrip() {
        let chats = [
            IvyChatReference(rawValue: "a:00000000-0000-4000-8000-000000000001")!,
            IvyChatReference(rawValue: "g:AAEC")!,
        ]
        write { tx in
            IvyHomeSettings.setImportantChats(chats, tx: tx)
        }
        read { tx in
            XCTAssertEqual(IvyHomeSettings.importantChats(tx: tx), chats)
        }
    }

    func testImportantMessagesKeepTheirBestReason() {
        func message(_ id: String, _ timestamp: UInt64, _ reason: IvyImportantMessage.Reason) -> IvyImportantMessage {
            IvyImportantMessage(threadUniqueId: "thread", messageUniqueId: id, timestamp: timestamp, reason: reason)
        }
        let merged = IvyImportantMessage.merged([
            message("a", 1, .pinnedChat),
            message("a", 1, .mention),
            message("b", 3, .reply),
            message("c", 2, .importantChat),
            message("d", 4, .pinnedChat),
        ], limit: 3)
        XCTAssertEqual(merged.map(\.messageUniqueId), ["d", "b", "c"])

        let all = IvyImportantMessage.merged([message("a", 1, .pinnedChat), message("a", 1, .mention)], limit: 10)
        XCTAssertEqual(all.map(\.reason), [.mention])
    }

    func testFindsNothingWithoutMessages() {
        read { tx in
            XCTAssertTrue(IvyImportantMessage.find(importantChats: [], dueReminderMessages: [], limit: 10, tx: tx).isEmpty)
        }
    }
}
