//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvySharedPlansTest: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private var plan: IvyPlan {
        IvyPlan(
            id: "plan-1",
            title: "Dinner",
            location: "Luigi's",
            options: [
                IvyPlan.Option(number: 1, start: start, end: start.addingTimeInterval(7200)),
                IvyPlan.Option(number: 2, start: start.addingTimeInterval(86_400), end: start.addingTimeInterval(86_400 + 7200)),
            ],
        )
    }

    func testProposalRoundTrip() throws {
        let ics = IvySharedPlans.ics(for: plan)
        XCTAssertTrue(ics.contains("STATUS:TENTATIVE"))
        let parsed = try XCTUnwrap(IvySharedPlans.plan(fromICS: ics))
        XCTAssertEqual(parsed, plan)
    }

    func testConfirmationRoundTrip() throws {
        let confirmed = try XCTUnwrap(plan.confirmed(option: 2))
        XCTAssertTrue(confirmed.isConfirmed)
        XCTAssertEqual(confirmed.options.map(\.number), [2])
        let ics = IvySharedPlans.ics(for: confirmed)
        XCTAssertTrue(ics.contains("STATUS:CONFIRMED"))
        let parsed = try XCTUnwrap(IvySharedPlans.plan(fromICS: ics))
        XCTAssertTrue(parsed.isConfirmed)
        XCTAssertEqual(parsed.id, "plan-1")
        XCTAssertEqual(parsed.options.first?.start, start.addingTimeInterval(86_400))
        XCTAssertEqual(IvySharedPlans.event(forConfirmed: parsed)?.importedUID, "plan-1@ivy-plan")
    }

    func testOtherCalendarFilesAreNotPlans() {
        let ics = IvyICS.export([IvyEvent(title: "Trip", startAt: start, endAt: start.addingTimeInterval(3600))])
        XCTAssertNil(IvySharedPlans.plan(fromICS: ics))
    }

    func testAnswerNumbers() {
        XCTAssertEqual(IvySharedPlans.answerNumber(in: IvySharedPlans.answerText(number: 2, detail: "Sat")), 2)
        XCTAssertEqual(IvySharedPlans.answerNumber(in: "1"), 1)
        XCTAssertEqual(IvySharedPlans.answerNumber(in: " 3) works for me"), 3)
        XCTAssertEqual(IvySharedPlans.answerNumber(in: "✔️ 2"), 2)
        XCTAssertNil(IvySharedPlans.answerNumber(in: "2026 is a good year"))
        XCTAssertNil(IvySharedPlans.answerNumber(in: "12pm works"))
        XCTAssertNil(IvySharedPlans.answerNumber(in: "sure"))
    }

    func testLatestAnswerCounts() {
        let answers = [
            IvySharedPlans.Answer(voter: "Alex", number: 1, timestamp: 1),
            IvySharedPlans.Answer(voter: "Alex", number: 2, timestamp: 5),
            IvySharedPlans.Answer(voter: "Sam", number: 2, timestamp: 3),
            IvySharedPlans.Answer(voter: "Kim", number: 9, timestamp: 4),
        ]
        let tally = IvySharedPlans.tally(answers, plan: plan)
        XCTAssertEqual(tally[2], ["Alex", "Sam"])
        XCTAssertNil(tally[1])
        XCTAssertNil(tally[9])
    }
}
