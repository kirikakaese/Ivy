//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyTaskPhrasesTest: XCTestCase {

    private func titles(_ text: String) -> [String] {
        IvyTaskPhrases.phrases(in: text).map(\.title)
    }

    func testRequests() {
        XCTAssertEqual(titles("Hey! Can you pick up milk on the way home?"), ["Pick up milk on the way home"])
        XCTAssertEqual(titles("Could you please send me the file"), ["Send me the file"])
        XCTAssertEqual(titles("Don't forget to call mom."), ["Call mom"])
        XCTAssertEqual(titles("todo: buy milk"), ["Buy milk"])
        XCTAssertEqual(titles("Can you buy bread? And please call Tom."), ["Buy bread", "Call Tom"])
    }

    func testGerman() {
        XCTAssertEqual(titles("Vergiss nicht, Oma anzurufen."), ["Oma anzurufen"])
        XCTAssertEqual(titles("Kannst du bitte den Müll rausbringen?"), ["Den Müll rausbringen"])
        XCTAssertEqual(titles("Bitte ruf mich an"), ["Ruf mich an"])
    }

    func testNotRequests() {
        XCTAssertEqual(titles("yes please"), [])
        XCTAssertEqual(titles("Can you?"), [])
        XCTAssertEqual(titles("Thanks, see you later!"), [])
        XCTAssertEqual(titles("The canyon was huge"), [])
    }

    func testTimesStayInTheSentence() {
        XCTAssertEqual(titles("Don't forget the meeting at 10.30 please"), ["The meeting at 10.30"])
    }

    func testStopsBeforeOtherItems() {
        let text = "Can you call the dentist tomorrow at 10?"
        let date = (text as NSString).range(of: "tomorrow at 10")
        let phrases = IvyTaskPhrases.phrases(in: text, avoiding: [date])
        XCTAssertEqual(phrases.map(\.text), ["Can you call the dentist"])
        XCTAssertEqual(phrases.map(\.title), ["Call the dentist"])
        XCTAssertEqual(phrases.first?.range, NSRange(location: 0, length: 24))

        let covered = IvyTaskPhrases.phrases(in: "Please see https://example.com", avoiding: [NSRange(location: 0, length: 30)])
        XCTAssertEqual(covered, [])
    }

    func testRangesCountUTF16() {
        let text = "👋 Can you water the plants"
        let phrase = IvyTaskPhrases.phrases(in: text).first
        XCTAssertEqual(phrase?.range, (text as NSString).range(of: "Can you water the plants"))
    }

    func testDataItemsDoNotOverlap() throws {
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let items = TextCheckingDataItem.detectedItems(in: "Can you read the post https://example.com today", using: detector)
        XCTAssertEqual(items.map(\.dataType), [.link, .task])
        XCTAssertEqual(items.last?.snippet, "Can you read the post")
    }
}
