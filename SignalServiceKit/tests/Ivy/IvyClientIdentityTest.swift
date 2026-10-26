//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyClientIdentityTest: XCTestCase {

    /// Ivy reports the upstream release it is built on, including its build
    /// number, in the same form as the official client.
    func testReportsUpstreamReleaseVersion() throws {
        let version = AppVersionImpl.shared.currentAppVersion
        let components = version.split(separator: ".")
        XCTAssertEqual(components.count, 4, version)
        XCTAssertNotEqual(components.last, "0", "The build number of the upstream release is missing: \(version)")
        _ = try AppVersionNumber4(AppVersionNumber(version))
    }

    func testUserAgentNamesTheUpstreamClient() {
        let version = AppVersionImpl.shared.currentAppVersion
        XCTAssertTrue(
            HttpHeaders.userAgentHeaderValueSignalIos.hasPrefix("Signal-iOS/\(version) iOS/"),
            HttpHeaders.userAgentHeaderValueSignalIos,
        )
    }

    /// Ivy's own build count after the upstream build number never reaches
    /// the servers.
    func testIvyBuildCountStaysLocal() {
        XCTAssertEqual(AppVersionImpl.ivyClientBuildNumber("1910.42"), "1910")
        XCTAssertEqual(AppVersionImpl.ivyClientBuildNumber("1910"), "1910")
    }
}
