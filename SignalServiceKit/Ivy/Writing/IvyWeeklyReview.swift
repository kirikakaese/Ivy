//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications

/// A look at the week, offered once a week at a time the user chooses:
/// overdue and open tasks, the next seven days' events, and chats waiting
/// for an answer. The time stays on this device.
public enum IvyWeeklyReview {

    public static let categoryIdentifier = "Ivy.weeklyReview"
    static let identifier = "ivy-weekly-review"

    private static let store = KeyValueStore(collection: "IvyWeeklyReview")
    private static let weekdayKey = "weekday"
    private static let minutesKey = "minutes"

    /// When the review is offered.
    public struct Time: Equatable, Sendable {
        /// 1 is Sunday, as `Calendar` counts.
        public var weekday: Int
        /// Minutes after midnight.
        public var minutes: Int

        public init(weekday: Int, minutes: Int) {
            self.weekday = weekday
            self.minutes = minutes
        }

        /// Sunday at 18:00.
        public static let suggested = Time(weekday: 1, minutes: 18 * 60)
    }

    // MARK: - Setting

    public static func time(tx: DBReadTransaction) -> Time? {
        guard
            let weekday = store.getInt(weekdayKey, transaction: tx),
            let minutes = store.getInt(minutesKey, transaction: tx)
        else {
            return nil
        }
        return Time(weekday: weekday, minutes: minutes)
    }

    public static func setTime(_ time: Time?, tx: DBWriteTransaction) {
        if let time {
            store.setInt(time.weekday, key: weekdayKey, transaction: tx)
            store.setInt(time.minutes, key: minutesKey, transaction: tx)
        } else {
            store.removeValues(forKeys: [weekdayKey, minutesKey], transaction: tx)
        }
    }

    // MARK: - Contents

    public struct Contents: Equatable, Sendable {
        public var overdueTasks: [IvyTask]
        /// Due in the next seven days.
        public var dueTasks: [IvyTask]
        /// Without a due date.
        public var somedayTasks: [IvyTask]
        public var events: [IvyCalendarItem]
    }

    static let days = 7

    public static func contents(tasks: [IvyTask], events: [IvyEvent], now: Date, calendar: Calendar = .current) -> Contents {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(TimeInterval(days * 86_400))
        let open = tasks.filter { !$0.isDone }
        let overdue = open.filter { $0.isOverdue(at: now, calendar: calendar) }
        let due = open.filter { task in
            guard let dueAt = task.dueAt, !task.isOverdue(at: now, calendar: calendar) else {
                return false
            }
            return dueAt < end
        }
        let byDue: (IvyTask, IvyTask) -> Bool = { ($0.dueAt ?? .distantFuture, $0.id) < ($1.dueAt ?? .distantFuture, $1.id) }
        return Contents(
            overdueTasks: overdue.sorted(by: byDue),
            dueTasks: due.sorted(by: byDue),
            somedayTasks: open.filter { $0.dueAt == nil }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) },
            events: IvyCalendar.items(events: events, tasks: [], reminders: [], in: DateInterval(start: start, end: end), calendar: calendar)
                .sorted { ($0.start, $0.id) < ($1.start, $1.id) },
        )
    }

    // MARK: - Notification

    public static func isReview(_ request: UNNotificationRequest) -> Bool {
        request.identifier == identifier
    }

    /// Schedules the weekly notification, or removes it.
    public static func reschedule() {
        let time = SSKEnvironment.shared.databaseStorageRef.read { tx in self.time(tx: tx) }
        let center = UNUserNotificationCenter.current()
        guard let time else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = IvyLocalizedString("WEEKLY_REVIEW_TITLE", comment: "Title of the weekly review of tasks, events and chats.")
        content.body = IvyLocalizedString("WEEKLY_REVIEW_NOTIFICATION", comment: "Text of the weekly notification that offers the review.")
        content.categoryIdentifier = categoryIdentifier
        let components = DateComponents(hour: time.minutes / 60, minute: time.minutes % 60, weekday: time.weekday)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true),
        )
        center.add(request) { error in
            if let error {
                Logger.warn("Couldn't schedule the weekly review: \(error)")
            }
        }
    }
}
