//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications

/// Local notifications for tasks that remind when they're due. Like
/// reminders, each device schedules its own, and a task finished on one
/// device removes the notification on the others once the change arrives.
public enum IvyTaskNotifications {

    public static let categoryIdentifier = "Ivy.task"
    static let identifierPrefix = "ivy-task-"

    public enum Action: String, CaseIterable {
        case done = "Ivy.task.done"
        case tomorrow = "Ivy.task.tomorrow"
    }

    public static let taskIdKey = "Ivy.taskId"

    public static var categories: Set<UNNotificationCategory> {
        let actions = [
            UNNotificationAction(
                identifier: Action.done.rawValue,
                title: IvyLocalizedString("TASK_MARK_DONE", comment: "Action that marks a task as done."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "checkmark"),
            ),
            UNNotificationAction(
                identifier: Action.tomorrow.rawValue,
                title: IvyLocalizedString("TASK_DUE_TOMORROW", comment: "Action that moves a task's due date to tomorrow."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "sunrise"),
            ),
        ]
        return [UNNotificationCategory(identifier: categoryIdentifier, actions: actions, intentIdentifiers: [], options: [])]
    }

    public static func isTask(_ request: UNNotificationRequest) -> Bool {
        return request.content.categoryIdentifier == categoryIdentifier
    }

    public static func taskId(of request: UNNotificationRequest) -> String? {
        guard isTask(request) else {
            return nil
        }
        return request.content.userInfo[taskIdKey] as? String
    }

    /// The tasks that need a notification after `now`, with its date.
    public static func scheduled(_ tasks: [IvyTask], after now: Date, calendar: Calendar = .current) -> [(IvyTask, Date)] {
        return tasks.compactMap { task in
            guard let date = task.reminderDate(calendar: calendar), date > now else {
                return nil
            }
            return (task, date)
        }
    }

    /// Makes the scheduled notifications match the tasks.
    public static func reschedule(_ tasks: [IvyTask], listNames: [String: String]) async {
        let center = UNUserNotificationCenter.current()
        let wanted = scheduled(tasks, after: Date())
        let wantedIds = Set(wanted.map { identifierPrefix + $0.0.id })

        let pending = await center.pendingNotificationRequests().filter(isTask)
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !wantedIds.contains($0) })
        let openIds = Set(tasks.filter { !$0.isDone }.map { identifierPrefix + $0.id })
        let delivered = await center.deliveredNotifications().map(\.request).filter(isTask)
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.identifier).filter { !openIds.contains($0) })

        for (task, date) in wanted {
            let content = UNMutableNotificationContent()
            content.title = task.title
            var details = [String]()
            if let listName = task.listId.flatMap({ listNames[$0] }) {
                details.append(listName)
            }
            if let firstLine = task.notes.split(whereSeparator: \.isNewline).first {
                details.append(String(firstLine))
            }
            content.body = details.isEmpty
                ? IvyLocalizedString("TASK_NOTIFICATION_BODY", comment: "Body of the notification when a task is due and has no notes or list.")
                : details.joined(separator: " · ")
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.threadIdentifier = categoryIdentifier
            content.userInfo = [taskIdKey: task.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: identifierPrefix + task.id, content: content, trigger: trigger))
            } catch {
                Logger.warn("Couldn't schedule a task notification: \(error)")
            }
        }
    }
}
