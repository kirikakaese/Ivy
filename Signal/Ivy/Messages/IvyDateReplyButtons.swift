//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// "Zusagen / Absagen / Kalender" in a row under incoming messages that name
/// an upcoming date. Accepting puts the event into Ivy's calendar and sends a
/// short quoted reply; declining only replies. Replies are plain text, so
/// people on Signal read them like any other message.
enum IvyDateReplyButtons {

    enum Choice: Equatable {
        case accept
        case decline
        case calendar
    }

    /// The buttons for a message, or nil when it gets none. Answered
    /// messages show what was answered instead.
    static func actions(for message: TSMessage, hasPendingMessageRequest: Bool, tx: DBReadTransaction) -> [CVMessageAction]? {
        guard
            let incoming = message as? TSIncomingMessage,
            !hasPendingMessageRequest,
            !incoming.wasRemotelyDeleted,
            IvyMessageDetection.detectsDates,
            IvyDateReplies.showsButtons,
            let text = incoming.body?.nilIfEmpty,
            let detected = IvyDateReplies.date(
                in: text,
                messageDate: Date(millisecondsSince1970: incoming.receivedAtTimestamp),
            ),
            IvySharedPlans.plan(in: incoming, tx: tx) == nil
        else {
            return nil
        }
        let id = incoming.uniqueId
        switch IvyDateReplies.answer(forMessage: id) {
        case .accept:
            return [CVMessageAction(title: "✓ " + acceptedTitle + " · " + shortDateText(detected), accessibilityIdentifier: "ivy_date_accepted", action: .none)]
        case .decline:
            return [CVMessageAction(title: "✕ " + declinedTitle + " · " + shortDateText(detected), accessibilityIdentifier: "ivy_date_declined", action: .none)]
        case nil:
            return [
                CVMessageAction(title: "✓ " + acceptTitle, accessibilityIdentifier: "ivy_date_accept", action: .ivyDateReply(messageUniqueId: id, choice: .accept)),
                CVMessageAction(title: "✕ " + declineTitle, accessibilityIdentifier: "ivy_date_decline", action: .ivyDateReply(messageUniqueId: id, choice: .decline)),
                CVMessageAction(title: "+ " + calendarTitle, accessibilityIdentifier: "ivy_date_calendar", action: .ivyDateReply(messageUniqueId: id, choice: .calendar)),
            ]
        }
    }

    /// "Sa., 14. Nov., 18:00", or without the time for a whole day.
    static func shortDateText(_ detected: IvyDetectedDate) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(detected.isAllDay ? "EEEdMMM" : "EEEdMMMHHmm")
        return formatter.string(from: detected.date)
    }

    // MARK: Strings

    static var acceptTitle: String {
        IvyLocalizedString("DATE_REPLY_ACCEPT", comment: "Button under a message with a date: accept, add it to the calendar and reply.")
    }

    static var declineTitle: String {
        IvyLocalizedString("DATE_REPLY_DECLINE", comment: "Button under a message with a date: decline and reply.")
    }

    static var calendarTitle: String {
        IvyLocalizedString("DATE_REPLY_CALENDAR", comment: "Button under a message with a date: open a new calendar event for it.")
    }

    static var acceptedTitle: String {
        IvyLocalizedString("DATE_REPLY_ACCEPTED", comment: "Shown under a message with a date after accepting it, and in the reply that is sent.")
    }

    static var declinedTitle: String {
        IvyLocalizedString("DATE_REPLY_DECLINED", comment: "Shown under a message with a date after declining it, and in the reply that is sent.")
    }

    static var buttonsSettingTitle: String {
        IvyLocalizedString("DATE_REPLY_SETTING", comment: "Switch in the chat settings that shows accept and decline buttons under messages with a date.")
    }
}

extension ConversationViewController {

    func ivyDidTapDateReply(messageUniqueId: String, choice: IvyDateReplyButtons.Choice) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard
            let message = databaseStorage.read(block: { tx in
                TSMessage.fetchMessageViaCache(uniqueId: messageUniqueId, transaction: tx)
            }),
            let text = message.body?.nilIfEmpty,
            let detected = IvyDateReplies.date(in: text, messageDate: Date(millisecondsSince1970: message.receivedAtTimestamp))
        else {
            return
        }
        let source = IvyMessageReference(message: message, thread: thread).map {
            IvyTask.Source(message: $0, quote: IvyTask.quote(fromMessageText: text))
        }
        let title = IvyTaskPhrases.phrases(in: text, avoiding: []).first?.title ?? IvyTask.title(fromMessageText: text)
        let event = IvyEvent.draft(from: detected, title: title, source: source)

        let reply: IvyDateReply
        let replyText: String
        switch choice {
        case .calendar:
            ivyPresentEventEditor(event, isNew: true)
            return
        case .accept:
            reply = .accept
            replyText = "✓ " + IvyDateReplyButtons.acceptedTitle + " · " + IvyDateReplyButtons.shortDateText(detected)
            IvyEventManager.shared.save(event)
            presentToast(text: IvyLocalizedString("DATE_REPLY_ADDED_TOAST", comment: "Toast after accepting a date: the event is now in the calendar."))
        case .decline:
            reply = .decline
            replyText = "✕ " + IvyDateReplyButtons.declinedTitle + " · " + IvyDateReplyButtons.shortDateText(detected)
        }

        let quote = databaseStorage.read { tx in
            DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(
                originalMessage: message,
                loadNormalizedImage: NormalizedImage.loadImage(imageSource:maxPixelSize:),
                tx: tx,
            )
        }
        ThreadUtil.enqueueMessage(
            body: MessageBody(text: replyText, ranges: .empty),
            thread: thread,
            quotedReplyDraft: quote,
        )
        IvyDateReplies.record(reply, forMessage: messageUniqueId)
        // Redraw the message with the answer instead of the buttons.
        databaseStorage.asyncWrite { tx in
            databaseStorage.touch(interaction: message, shouldReindex: false, tx: tx)
        }
    }
}

extension ChatsSettingsViewController {

    /// The switch for the buttons, in the detection section.
    func ivyDateReplyButtonsItem() -> OWSTableItem {
        .switch(
            withText: IvyDateReplyButtons.buttonsSettingTitle,
            isOn: { IvyDateReplies.showsButtons },
            actionBlock: { uiSwitch in
                IvyDateReplies.showsButtons = uiSwitch.isOn
            },
        )
    }
}
