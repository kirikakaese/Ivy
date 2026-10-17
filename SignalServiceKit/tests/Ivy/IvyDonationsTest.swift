//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyDonationsTest: XCTestCase {

    private func manifest(
        conditionalId: String? = nil,
        primaryActionId: String? = nil,
        secondaryActionId: String? = nil,
    ) -> RemoteMegaphoneModel.Manifest {
        return RemoteMegaphoneModel.Manifest(
            id: "test",
            priority: 1,
            minAppVersion: "1.0.0",
            countries: "1:1000000",
            dontShowBefore: 0,
            dontShowAfter: 0,
            showForNumberOfDays: 1,
            conditionalCheck: conditionalId.map { .init(fromConditionalId: $0) },
            primaryAction: primaryActionId.map { .init(fromActionId: $0) },
            primaryActionData: nil,
            secondaryAction: secondaryActionId.map { .init(fromActionId: $0) },
            secondaryActionData: nil,
        )
    }

    func testDonationMegaphones() {
        XCTAssertTrue(manifest(conditionalId: "standard_donate").asksForDonation)
        XCTAssertTrue(manifest(primaryActionId: "donate").asksForDonation)
        XCTAssertTrue(manifest(primaryActionId: "finish", secondaryActionId: "donate_friend").asksForDonation)
    }

    func testOtherMegaphones() {
        XCTAssertFalse(manifest().asksForDonation)
        XCTAssertFalse(manifest(conditionalId: "internal_user", primaryActionId: "finish", secondaryActionId: "snooze").asksForDonation)
    }
}
