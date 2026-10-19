//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyPasscodeTest: XCTestCase {

    func testHashDependsOnSaltAndPasscode() {
        let salt = Data(repeating: 1, count: 16)
        let hash = IvyPasscode.hash("1234", salt: salt, iterations: 1000)
        XCTAssertEqual(hash.count, 32)
        XCTAssertEqual(hash, IvyPasscode.hash("1234", salt: salt, iterations: 1000))
        XCTAssertNotEqual(hash, IvyPasscode.hash("1235", salt: salt, iterations: 1000))
        XCTAssertNotEqual(hash, IvyPasscode.hash("1234", salt: Data(repeating: 2, count: 16), iterations: 1000))
    }

    func testDelayGrowsAfterFreeAttempts() {
        XCTAssertNil(IvyPasscode.delay(afterFailedAttempts: 1))
        XCTAssertNil(IvyPasscode.delay(afterFailedAttempts: IvyPasscode.freeAttempts - 1))
        XCTAssertEqual(IvyPasscode.delay(afterFailedAttempts: IvyPasscode.freeAttempts), 30)
        XCTAssertEqual(IvyPasscode.delay(afterFailedAttempts: IvyPasscode.freeAttempts + 1), 60)
        XCTAssertEqual(IvyPasscode.delay(afterFailedAttempts: 100), 60 * 60)
    }

    func testSettingCheckingAndRemoving() {
        let db = InMemoryDB()
        XCTAssertFalse(db.read { tx in IvyPasscode.isSet(tx: tx) })

        db.write { tx in IvyPasscode.set("secret", tx: tx) }
        XCTAssertTrue(db.read { tx in IvyPasscode.isSet(tx: tx) })
        XCTAssertEqual(db.write { tx in IvyPasscode.verify("wrong", tx: tx) }, .wrong)
        XCTAssertEqual(db.write { tx in IvyPasscode.verify("secret", tx: tx) }, .correct)

        db.write { tx in IvyPasscode.remove(tx: tx) }
        XCTAssertFalse(db.read { tx in IvyPasscode.isSet(tx: tx) })
    }

    func testWrongAttemptsBlock() {
        let db = InMemoryDB()
        let now = Date(timeIntervalSince1970: 1_000_000)
        db.write { tx in IvyPasscode.set("secret", tx: tx) }
        for _ in 1..<IvyPasscode.freeAttempts {
            XCTAssertEqual(db.write { tx in IvyPasscode.verify("wrong", now: now, tx: tx) }, .wrong)
        }
        let blocked = db.write { tx in IvyPasscode.verify("wrong", now: now, tx: tx) }
        XCTAssertEqual(blocked, .blocked(until: now.addingTimeInterval(30)))

        // Even the right passcode waits.
        XCTAssertEqual(db.write { tx in IvyPasscode.verify("secret", now: now.addingTimeInterval(10), tx: tx) }, blocked)
        // Afterwards it works and the count starts over.
        XCTAssertEqual(db.write { tx in IvyPasscode.verify("secret", now: now.addingTimeInterval(31), tx: tx) }, .correct)
        XCTAssertNil(db.read { tx in IvyPasscode.blockedUntil(now: now, tx: tx) })
    }
}
