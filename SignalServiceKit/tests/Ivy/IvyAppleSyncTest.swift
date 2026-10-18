//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyAppleSyncTest: XCTestCase {

    private func link(_ appleId: String, ivy: String = "i", apple: String = "a") -> IvyAppleLink {
        IvyAppleLink(appleId: appleId, ivyFingerprint: ivy, appleFingerprint: apple)
    }

    func testOffDoesNothing() {
        XCTAssertEqual(IvyAppleSync.plan(mode: .off, ivy: ["1": "i"], apple: ["A": "a"], links: [:]), [])
    }

    func testNewItems() {
        let ivy = ["1": "i"]
        let apple = ["A": "a"]
        XCTAssertEqual(IvyAppleSync.plan(mode: .copy, ivy: ivy, apple: apple, links: [:]), [.createInApple(ivyId: "1")])
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .twoWay, ivy: ivy, apple: apple, links: [:]),
            [.createInApple(ivyId: "1"), .createInIvy(appleId: "A")],
        )
    }

    func testUnchangedItemsStay() {
        let links = ["1": link("A")]
        XCTAssertEqual(IvyAppleSync.plan(mode: .twoWay, ivy: ["1": "i"], apple: ["A": "a"], links: links), [])
        XCTAssertEqual(IvyAppleSync.plan(mode: .copy, ivy: ["1": "i"], apple: ["A": "a"], links: links), [])
    }

    func testChanges() {
        let links = ["1": link("A")]
        // Changed in Ivy.
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .twoWay, ivy: ["1": "i2"], apple: ["A": "a"], links: links),
            [.updateApple(ivyId: "1", appleId: "A")],
        )
        // Changed in Apple: two-way takes it, a copy is put back.
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .twoWay, ivy: ["1": "i"], apple: ["A": "a2"], links: links),
            [.updateIvy(ivyId: "1", appleId: "A")],
        )
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .copy, ivy: ["1": "i"], apple: ["A": "a2"], links: links),
            [.updateApple(ivyId: "1", appleId: "A")],
        )
        // Changed on both sides: Ivy wins.
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .twoWay, ivy: ["1": "i2"], apple: ["A": "a2"], links: links),
            [.updateApple(ivyId: "1", appleId: "A")],
        )
    }

    func testDeletions() {
        let links = ["1": link("A")]
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .twoWay, ivy: [:], apple: ["A": "a"], links: links),
            [.deleteFromApple(appleId: "A")],
        )
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .copy, ivy: [:], apple: ["A": "a"], links: links),
            [.deleteFromApple(appleId: "A")],
        )
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .twoWay, ivy: ["1": "i"], apple: [:], links: links),
            [.deleteFromIvy(ivyId: "1")],
        )
        XCTAssertEqual(
            IvyAppleSync.plan(mode: .copy, ivy: ["1": "i"], apple: [:], links: links),
            [.createInApple(ivyId: "1")],
        )
        XCTAssertEqual(IvyAppleSync.plan(mode: .twoWay, ivy: [:], apple: [:], links: links), [.forget(ivyId: "1")])
    }

    func testFingerprintsIgnoreFractionsOfSeconds() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let event = IvyEvent(title: "Lunch", startAt: start, endAt: start.addingTimeInterval(3600))
        var shifted = event
        shifted.startAt = start.addingTimeInterval(0.4)
        XCTAssertEqual(IvyAppleEventFields(event).fingerprint, IvyAppleEventFields(shifted).fingerprint)

        var renamed = event
        renamed.title = "Dinner"
        XCTAssertNotEqual(IvyAppleEventFields(event).fingerprint, IvyAppleEventFields(renamed).fingerprint)

        // Alerts stay in Ivy and don't count.
        var alerted = event
        alerted.alertMinutes = 10
        XCTAssertEqual(IvyAppleEventFields(event).fingerprint, IvyAppleEventFields(alerted).fingerprint)
    }

    func testReminderFieldsKeepIvyOnlyParts() {
        let task = IvyTask(
            title: "Buy milk",
            reminds: true,
            listId: "list",
            subtasks: [.init(title: "Oat")],
            createdAt: Date(timeIntervalSince1970: 0),
        )
        let fields = IvyAppleReminderFields(
            title: "Buy oat milk",
            notes: "2 litres",
            dueAt: nil,
            isAllDay: true,
            priority: .high,
            isDone: true,
        )
        XCTAssertFalse(fields.isAllDay, "Without a due date nothing is all-day")
        let done = Date(timeIntervalSince1970: 100)
        let updated = fields.applied(to: task, now: done)
        XCTAssertEqual(updated.title, "Buy oat milk")
        XCTAssertEqual(updated.notes, "2 litres")
        XCTAssertEqual(updated.priority, .high)
        XCTAssertTrue(updated.isDone)
        XCTAssertEqual(updated.completedAt, done)
        XCTAssertEqual(updated.listId, "list")
        XCTAssertEqual(updated.subtasks, task.subtasks)
        XCTAssertTrue(updated.reminds)
        XCTAssertEqual(IvyAppleReminderFields(updated), fields)
    }

    func testPriorities() {
        for priority in IvyTask.Priority.allCases {
            XCTAssertEqual(IvyAppleReminderFields.priority(fromApple: IvyAppleReminderFields.applePriority(priority)), priority)
        }
        XCTAssertEqual(IvyAppleReminderFields.priority(fromApple: 3), .high)
        XCTAssertEqual(IvyAppleReminderFields.priority(fromApple: 7), .low)
    }
}
