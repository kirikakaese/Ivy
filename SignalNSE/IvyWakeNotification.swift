//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UserNotifications

/// Ivy's push relay wakes Ivy with an alert push. Apple shows that push
/// unless the notification service replaces its content; Signal hides its
/// wake-ups with the notification filtering entitlement, which Ivy doesn't
/// have. So the message notification Ivy posted while handling the push
/// becomes the push's content instead, and the user sees one notification.
enum IvyWakeNotification {

    static func content(
        replacing fallback: UNNotificationContent,
        wake request: UNNotificationRequest,
        handlingSince start: Date,
    ) async -> UNNotificationContent {
        guard !IvyConfiguration.usesApplePushNotifications else {
            return fallback
        }
        let center = UNUserNotificationCenter.current()
        let posted = await center.deliveredNotifications()
            .filter {
                $0.request.identifier != request.identifier
                    && !($0.request.trigger is UNPushNotificationTrigger)
                    && $0.date >= start.addingTimeInterval(-1)
            }
            .max { $0.date < $1.date }
        guard
            let posted,
            let content = posted.request.content.mutableCopy() as? UNMutableNotificationContent
        else {
            // Nothing new to show, for example a message read on another
            // device meanwhile; the push keeps its generic text.
            return fallback
        }
        center.removeDeliveredNotifications(withIdentifiers: [posted.request.identifier])
        content.badge = fallback.badge
        // The sound already played when Ivy posted the notification.
        content.sound = nil
        return content
    }
}
