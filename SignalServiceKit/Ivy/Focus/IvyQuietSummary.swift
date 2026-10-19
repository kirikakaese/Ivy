//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications

/// One notification a day, at a time the user chooses, that sums up the
/// unread messages in muted chats. It is kept up to date whenever a muted
/// chat gets a message and whenever Ivy comes to the front.
public enum IvyQuietSummary {

    static let identifier = "ivy-quiet-summary"
    public static let categoryIdentifier = "Ivy.quietSummary"

    private static let store = KeyValueStore(collection: "IvyQuietSummary")
    private static let timeKey = "time"

    /// Chats looked at, most recent first.
    static let maxChats = 500

    // MARK: - Setting

    /// Minutes after midnight, or nil when the summary is off.
    public static func time(tx: DBReadTransaction) -> Int? {
        store.getInt(timeKey, transaction: tx)
    }

    public static func setTime(_ minutes: Int?, tx: DBWriteTransaction) {
        if let minutes {
            store.setInt(minutes, key: timeKey, transaction: tx)
        } else {
            store.removeValue(forKey: timeKey, transaction: tx)
        }
    }

    // MARK: - Counting

    public struct Counts: Equatable, Sendable {
        public var chats: Int
        public var messages: Int
    }

    static func unreadMutedCounts(tx: DBReadTransaction) -> Counts {
        var counts = Counts(chats: 0, messages: 0)
        var chatsLookedAt = 0
        ThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
            guard chatsLookedAt < maxChats else {
                return
            }
            chatsLookedAt += 1
            guard thread.isMuted else {
                return
            }
            let unread = Int(InteractionFinder(threadUniqueId: thread.uniqueId).unreadCount(transaction: tx))
            if unread > 0 {
                counts.chats += 1
                counts.messages += unread
            }
        }
        return counts
    }

    /// The next time the summary is due after `now`.
    static func nextDate(minutes: Int, after now: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: minutes / 60, minute: minutes % 60),
            matchingPolicy: .nextTime,
        )
    }

    public static func body(for counts: Counts) -> String {
        String(
            format: IvyLocalizedString("QUIET_SUMMARY_BODY_FORMAT", comment: "Text of the daily summary of muted chats. Embeds {{ number of messages }} and {{ number of chats }}."),
            counts.messages.formatted(),
            counts.chats.formatted(),
        )
    }

    // MARK: - Scheduling

    public static func isSummary(_ request: UNNotificationRequest) -> Bool {
        request.identifier == identifier
    }

    private static let isRescheduling = AtomicBool(false, lock: .sharedGlobal)

    /// Reschedules a moment later, once, after messages in muted chats
    /// arrived. Safe to call inside a write transaction.
    public static func rescheduleSoon() {
        guard isRescheduling.tryToSetFlag() else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRescheduling.set(false)
            reschedule()
        }
    }

    /// Schedules the next summary with the current counts, or removes it.
    public static func reschedule() {
        let (minutes, counts) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (time(tx: tx), time(tx: tx) == nil ? nil : unreadMutedCounts(tx: tx))
        }
        let center = UNUserNotificationCenter.current()
        guard
            let minutes,
            let counts,
            counts.messages > 0,
            let date = nextDate(minutes: minutes, after: Date(), calendar: .current)
        else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = IvyLocalizedString("QUIET_SUMMARY_TITLE", comment: "Title of the daily summary of muted chats.")
        content.body = body(for: counts)
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = identifier
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false),
        )
        center.add(request) { error in
            if let error {
                Logger.warn("Couldn't schedule the quiet summary: \(error)")
            }
        }
    }
}
