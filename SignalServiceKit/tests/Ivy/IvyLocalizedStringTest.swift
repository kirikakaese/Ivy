//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyLocalizedStringTest: XCTestCase {

    private var bundleURL: URL!

    override func setUpWithError() throws {
        bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try write(["BOTH": "English both", "ENGLISH_ONLY": "English only"], locale: "en")
        // A language the test machine does not use, so lookups fall back to English.
        try write(["BOTH": "Klingon both"], locale: "tlh")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: bundleURL)
    }

    private func write(_ strings: [String: String], locale: String) throws {
        let directory = bundleURL.appendingPathComponent("\(locale).lproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: strings, format: .binary, options: 0)
        try data.write(to: directory.appendingPathComponent("\(IvyStrings.tableName).strings"))
    }

    func testEnglishString() throws {
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        XCTAssertEqual(IvyStrings.localizedString("ENGLISH_ONLY", bundle: bundle), "English only")
    }

    func testMissingStringReturnsKey() throws {
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        XCTAssertEqual(IvyStrings.localizedString("NOT_THERE", bundle: bundle), "NOT_THERE")
    }

    func testAppTableHasEnglish() throws {
        XCTAssertNotNil(Bundle.main.app.path(forResource: IvyStrings.tableName, ofType: "strings", inDirectory: nil, forLocalization: "en"))
    }
}
