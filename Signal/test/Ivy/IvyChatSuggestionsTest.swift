//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class IvyChatSuggestionsTest: XCTestCase {

    private let chats: [(threadId: String, name: String)] = [
        ("a", "karlsruhe buko delis 26"),
        ("b", "linksjugend ['solid'] Karlsruhe"),
        ("c", "Kreisvorstand Karlsruhe"),
        ("d", "19. BuKo Delegation BaWü"),
        ("e", "SHITPOSTING Linksjugend BW"),
        ("f", "Fynn"),
        ("g", "Partei-Stammtisch"),
    ]

    func testSuggestsChatsSharingWordsWithChosenOnes() {
        let suggestions = IvyChatSuggestions.suggest(chats: chats, selected: ["a", "b"], folderName: "")
        XCTAssertEqual(suggestions.first?.threadId, "c")
        XCTAssertEqual(suggestions.first?.word, "Karlsruhe")
        XCTAssertEqual(suggestions.first?.reason, .chosenChats(2))
        XCTAssertTrue(suggestions.contains { $0.threadId == "d" && $0.reason == .chosenChat("karlsruhe buko delis 26") })
        XCTAssertTrue(suggestions.contains { $0.threadId == "e" })
        XCTAssertFalse(suggestions.contains { $0.threadId == "f" || $0.threadId == "a" })
    }

    func testFolderNameAndFillerWords() {
        let suggestions = IvyChatSuggestions.suggest(chats: chats, selected: [], folderName: "Partei")
        XCTAssertEqual(suggestions.map(\.threadId), ["g"])
        XCTAssertEqual(suggestions.first?.reason, .folderName)
        XCTAssertTrue(IvyChatSuggestions.words("Chat für die WG 2026").isEmpty)
    }
}
