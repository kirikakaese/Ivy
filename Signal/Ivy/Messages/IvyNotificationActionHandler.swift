//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Carries out Ivy's actions on message notifications
/// (SignalServiceKit/Ivy/Messages/IvyNotificationActions.swift). Each one
/// marks the message as read, like Signal's own thumbs up.
enum IvyNotificationActionHandler {

    /// Returns false for other actions.
    @MainActor
    static func handle(_ response: UNNotificationResponse) -> Bool {
        guard let action = IvyNotificationActions.Action(rawValue: response.actionIdentifier) else {
            return false
        }
        let userInfo = AppNotificationUserInfo(response.notification.request.content.userInfo)
        guard
            let threadId = userInfo.threadId,
            let messageId = userInfo.messageId
        else {
            return true
        }
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard let (thread, message) = databaseStorage.read(block: { tx -> (TSThread, TSIncomingMessage)? in
            guard
                let thread = TSThread.fetchViaCache(uniqueId: threadId, transaction: tx),
                let message = TSInteraction.fetchViaCache(uniqueId: messageId, transaction: tx) as? TSIncomingMessage
            else {
                return nil
            }
            return (thread, message)
        }) else {
            return true
        }

        switch action {
        case .heart:
            databaseStorage.asyncWrite { tx in
                ReactionManager.localUserReacted(to: message.uniqueId, emoji: "❤️", isRemoving: false, isHighPriority: false, tx: tx)
            }
        case .remindInAnHour:
            if let chat = IvyChatReference(thread: thread) {
                IvyReminderManager.shared.add(IvyReminder(
                    chat: chat,
                    message: IvyMessageReference(message: message, thread: thread),
                    dueAt: Date().addingTimeInterval(60 * 60),
                ))
            }
        case .accept:
            IvyDateReplyButtons.answer(.accept, to: message, in: thread)
        case .decline:
            IvyDateReplyButtons.answer(.decline, to: message, in: thread)
        }

        Task {
            let hasPendingMessageRequest = databaseStorage.read { tx in thread.hasPendingMessageRequest(transaction: tx) }
            await SSKEnvironment.shared.receiptManagerRef.markAsReadLocally(
                beforeSortId: message.sortId,
                thread: thread,
                hasPendingMessageRequest: hasPendingMessageRequest,
            )
        }
        return true
    }
}
