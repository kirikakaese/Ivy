//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IvyGlanceTest: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testLinksRoundTrip() {
        let links: [IvyLink] = [.home, .chats, .calendar, .calls, .tasks, .newTask, .newEvent, .task(id: "a b"), .event(id: "E1")]
        for link in links {
            XCTAssertEqual(IvyLink(url: link.url), link, link.url.absoluteString)
        }
        XCTAssertEqual(IvyLink.task(id: "T1").url.absoluteString, "sgnl://ivy/task?id=T1")
    }

    func testOtherLinksAreNotIvyLinks() {
        XCTAssertNil(IvyLink(url: URL(string: "sgnl://linkdevice?uuid=x")!))
        XCTAssertNil(IvyLink(url: URL(string: "sgnl://ivy/unknown")!))
        XCTAssertNil(IvyLink(url: URL(string: "sgnl://ivy/task")!))
        XCTAssertNil(IvyLink(url: URL(string: "https://ivy/home")!))
    }

    func testTodayRemaining() {
        func item(_ id: String, start: Date, end: Date, allDay: Bool = false) -> IvyGlance.Item {
            IvyGlance.Item(id: id, kind: .event, title: id, start: start, end: end, isAllDay: allDay, link: IvyLink.event(id: id).url)
        }
        let glance = IvyGlance(
            writtenAt: date(8),
            unreadCount: 2,
            today: [
                item("allDay", start: date(0), end: date(0), allDay: true),
                item("breakfast", start: date(8), end: date(9)),
                item("lunch", start: date(12), end: date(13)),
            ],
            tasks: [],
            openTaskCount: 0,
        )
        XCTAssertEqual(glance.todayRemaining(at: date(10), calendar: calendar).map(\.id), ["allDay", "lunch"])
        XCTAssertEqual(glance.todayRemaining(at: date(8, 30), calendar: calendar).map(\.id), ["allDay", "breakfast", "lunch"])
        // A glance from yesterday knows nothing about today.
        XCTAssertEqual(glance.todayRemaining(at: date(10, day: 19), calendar: calendar), [])
    }

    func testEncodingRoundTrip() throws {
        let glance = IvyGlance(
            writtenAt: Date(timeIntervalSince1970: 1_790_000_000),
            unreadCount: 3,
            today: [],
            tasks: [IvyGlance.Item(id: "t", kind: .task, title: "Call Anna", start: nil, end: nil, isAllDay: false, link: IvyLink.task(id: "t").url)],
            openTaskCount: 12,
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(glance.encoded()).write(to: url)
        XCTAssertEqual(IvyGlance.read(from: url), glance)
    }

    func testListsAreCapped() {
        let items = (0..<20).map {
            IvyGlance.Item(id: "\($0)", kind: .task, title: "\($0)", start: nil, end: nil, isAllDay: false, link: IvyLink.tasks.url)
        }
        let glance = IvyGlance(writtenAt: Date(), unreadCount: 0, today: items, tasks: items, openTaskCount: 20)
        XCTAssertEqual(glance.today.count, IvyGlance.maxItems)
        XCTAssertEqual(glance.tasks.count, IvyGlance.maxItems)
        XCTAssertEqual(glance.openTaskCount, 20)
    }
}
