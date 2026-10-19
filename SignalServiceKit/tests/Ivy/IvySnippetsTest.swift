//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import XCTest

@testable import SignalServiceKit

final class IvySnippetsTest: XCTestCase {

    private let snippets = [
        IvySnippet(id: "1", trigger: "addr", text: "Main Street 1"),
        IvySnippet(id: "2", trigger: "omw", text: "On my way!"),
    ]

    private func expand(_ text: String) -> String? {
        let cursor = (text as NSString).length
        guard let expansion = IvySnippets.expansion(in: text, cursor: cursor, snippets: snippets) else {
            return nil
        }
        return (text as NSString).replacingCharacters(in: expansion.range, with: expansion.text)
    }

    func testExpandsAfterTheWord() {
        XCTAssertEqual(expand(";addr "), "Main Street 1 ")
        XCTAssertEqual(expand("I live at ;addr."), "I live at Main Street 1.")
        XCTAssertEqual(expand("Hi\n;OMW\n"), "Hi\nOn my way!\n")
    }

    func testLeavesOtherTextAlone() {
        XCTAssertNil(expand(";addr"))
        XCTAssertNil(expand(";nope "))
        XCTAssertNil(expand("a;addr "))
        XCTAssertNil(expand("addr "))
        XCTAssertNil(expand("; "))
    }

    func testTriggersAreCleaned() {
        XCTAssertEqual(IvySnippet.cleanTrigger(" My Addr! "), "myaddr")
        XCTAssertEqual(IvySnippet.cleanTrigger(String(repeating: "a", count: 40)).count, IvySnippet.maxTriggerLength)
    }

    func testSnippetsSync() throws {
        let phone = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 1 }))
        let mac = try IvyDataStore(database: DatabaseQueue(), clock: IvyDataClock(deviceId: { 2 }))
        var changes = [IvyDataChange]()
        phone.onLocalChanges = { changes += $0 }

        IvySnippets.save(IvySnippet(id: "s", trigger: "Addr", text: "Main Street 1"), store: phone)
        mac.apply(changes)
        XCTAssertEqual(IvySnippets.all(store: mac), [IvySnippet(id: "s", trigger: "addr", text: "Main Street 1")])

        IvySnippets.delete(id: "s", store: mac)
        XCTAssertTrue(IvySnippets.all(store: mac).isEmpty)
    }
}
