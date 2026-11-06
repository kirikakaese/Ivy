//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications

/// Ivy's extra actions on message notifications: a heart reaction and a
/// reminder in an hour on every message, and accept or decline first on
/// messages that name an upcoming date. Signal/Ivy/Messages/
/// IvyNotificationActionHandler.swift carries them out.
public enum IvyNotificationActions {

    /// These are persisted (via notifications) and must remain stable.
    public enum Action: String {
        case heart = "Ivy.Notification.Action.heart"
        case remindInAnHour = "Ivy.Notification.Action.remindInAnHour"
        case accept = "Ivy.Notification.Action.accept"
        case decline = "Ivy.Notification.Action.decline"
    }

    /// Messages that name an upcoming date, which can be replied to.
    public static let dateCategoryIdentifier = "Ivy.Notification.Category.messageWithDate"

    static func action(_ action: Action) -> UNNotificationAction {
        switch action {
        case .heart:
            return UNNotificationAction(
                identifier: action.rawValue,
                title: IvyLocalizedString("NOTIFICATION_REACT_HEART", comment: "Notification action that reacts to the message with a heart."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "heart"),
            )
        case .remindInAnHour:
            return UNNotificationAction(
                identifier: action.rawValue,
                title: IvyLocalizedString("NOTIFICATION_REMIND_IN_AN_HOUR", comment: "Notification action that sets a reminder for the message in one hour."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "alarm"),
            )
        case .accept:
            return UNNotificationAction(
                identifier: action.rawValue,
                title: IvyLocalizedString("DATE_REPLY_ACCEPT", comment: "Button under a message with a date: accept, add it to the calendar and reply."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"),
            )
        case .decline:
            return UNNotificationAction(
                identifier: action.rawValue,
                title: IvyLocalizedString("DATE_REPLY_DECLINE", comment: "Button under a message with a date: decline and reply."),
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "xmark.circle"),
            )
        }
    }

    /// Added after Signal's actions on messages that can be replied to.
    static var extraMessageActions: [UNNotificationAction] {
        [action(.heart), action(.remindInAnHour)]
    }

    /// The category for messages with a date: accept and decline first,
    /// then the usual actions.
    static func categories(messageActions: [UNNotificationAction]) -> Set<UNNotificationCategory> {
        [UNNotificationCategory(
            identifier: dateCategoryIdentifier,
            actions: [action(.accept), action(.decline)] + messageActions,
            intentIdentifiers: [],
            options: [],
        )]
    }

    /// The category a message notification is posted with: the date one
    /// when Signal's category allows replies and the text names an
    /// upcoming date (only when previews show the text).
    static func categoryIdentifier(signalCategory: String, canReply: Bool, body: String, now: Date = Date()) -> String {
        guard
            canReply,
            IvyMessageDetection.detectsDates,
            IvyDateReplies.showsButtons,
            IvyDateReplies.date(in: body, messageDate: now, now: now) != nil
        else {
            return signalCategory
        }
        return dateCategoryIdentifier
    }
}
