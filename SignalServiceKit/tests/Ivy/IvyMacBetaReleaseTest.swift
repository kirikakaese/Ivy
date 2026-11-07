//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyMacBetaReleaseTest: XCTestCase {

    private let sha = String(repeating: "ab", count: 32)

    private func release(_ tag: String, notes: String? = nil, asset: String = "Ivy-Mac-Beta.zip", draft: Bool = false) -> [String: Any] {
        [
            "tag_name": tag,
            "draft": draft,
            "body": notes ?? "Mac beta built from abc123.\n\nSHA-256: \(sha)\n",
            "assets": [["name": asset, "browser_download_url": "https://github.com/x/\(tag)/\(asset)"]],
        ]
    }

    func testPicksTheNewestBeta() throws {
        let json = try JSONSerialization.data(withJSONObject: [
            release("mac-beta-134"),
            release("catalyst-libsignal-v0.105.0-2", asset: "libsignal.tar.gz"),
            release("mac-beta-136"),
            release("mac-beta-140", draft: true),
            release("mac-beta-139", notes: "no checksum"),
            release("mac-beta-135"),
        ])
        let newest = try XCTUnwrap(IvyMacBetaRelease.newest(inReleasesJSON: json))
        XCTAssertEqual(newest.number, 136)
        XCTAssertEqual(newest.sha256, sha)
        XCTAssertEqual(newest.zipURL.absoluteString, "https://github.com/x/mac-beta-136/Ivy-Mac-Beta.zip")
    }

    func testChecksumComesFromTheNotes() {
        XCTAssertEqual(IvyMacBetaRelease.sha256(inNotes: "SHA-256: \(sha)"), sha)
        XCTAssertNil(IvyMacBetaRelease.sha256(inNotes: "SHA-256: short"))
        XCTAssertNil(IvyMacBetaRelease.newest(inReleasesJSON: Data("not json".utf8)))
    }
}
