//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications

/// Local notifications for reminders. Each device schedules its own
/// notification for every open reminder; when a reminder is handled on one
/// device, the others remove theirs as soon as the change arrives.
public enum IvyReminderNotifications {

    public static let categoryIdentifier = "Ivy.reminder"
    static let identifierPrefix = "ivy-reminder-"

    public enum Action: String, CaseIterable {
        case snoozeOneHour = "Ivy.reminder.snooze"
        case tomorrow = "Ivy.reminder.tomorrow"
        case done = "Ivy.reminder.done"
    }

    /// The key of the reminder id in a notification's userInfo. Upstream
    /// keys are not used, so that opening the chat doesn't remove pending
    /// reminders.
    public static let reminderIdKey = "Ivy.reminderId"

    public static var categories: Set<UNNotificationCategory> {
        let actions = [
            UNNotificationAction(
                identifier: Action.snoozeOneHour.rawValue,
                title: IvyLocalizedString("REMINDER_SNOOZE_ONE_HOUR", comment: "Notification action that reminds the user again in one hour."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"),
            ),
            UNNotificationAction(
                identifier: Action.tomorrow.rawValue,
                title: IvyLocalizedString("REMINDER_TOMORROW", comment: "Notification action that reminds the user again tomorrow morning."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "sunrise"),
            ),
            UNNotificationAction(
                identifier: Action.done.rawValue,
                title: IvyLocalizedString("REMINDER_DONE", comment: "Notification action that marks a reminder as done."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "checkmark"),
            ),
        ]
        return [UNNotificationCategory(identifier: categoryIdentifier, actions: actions, intentIdentifiers: [], options: [])]
    }

    public static func isReminder(_ request: UNNotificationRequest) -> Bool {
        return request.content.categoryIdentifier == categoryIdentifier
    }

    public static func reminderId(of request: UNNotificationRequest) -> String? {
        guard isReminder(request) else {
            return nil
        }
        return request.content.userInfo[reminderIdKey] as? String
    }

    /// Makes the scheduled notifications match the open reminders.
    public static func reschedule(_ reminders: [IvyReminder], titles: [String: String], bodies: [String: String]) async {
        let center = UNUserNotificationCenter.current()
        let open = reminders.filter { !$0.isDone }
        let wanted = Set(open.map { identifierPrefix + $0.id })

        let pending = await center.pendingNotificationRequests().filter(isReminder)
        let delivered = await center.deliveredNotifications().map(\.request).filter(isReminder)
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !wanted.contains($0) })
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.identifier).filter { !wanted.contains($0) })

        // Reminders that are already due were shown when they came due, or
        // came due while this device was away; the chat list shows them.
        for reminder in open where reminder.dueAt > Date() {
            let identifier = identifierPrefix + reminder.id
            let content = UNMutableNotificationContent()
            content.title = titles[reminder.id] ?? ""
            content.body = bodies[reminder.id] ?? ""
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.threadIdentifier = identifierPrefix + reminder.chat.rawValue
            content.userInfo = [reminderIdKey: reminder.id]
            let interval = max(reminder.dueAt.timeIntervalSinceNow, 1)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            } catch {
                Logger.warn("Couldn't schedule a reminder: \(error)")
            }
        }
    }
}
