//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum IvyDetectedItemsUI {

    /// The date a tapped snippet names. The whole message is read first, so
    /// "Friday at 5" keeps its context.
    static func date(for snippet: String, in text: String) -> IvyDetectedDate? {
        IvyDateDetection.dates(in: text).first { $0.text == snippet } ?? IvyDateDetection.dates(in: snippet).first
    }

    static func dateText(_ detected: IvyDetectedDate) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .full
        formatter.timeStyle = detected.isAllDay ? .none : .short
        return formatter.string(from: detected.date)
    }

    static func task(title: String, date: IvyDetectedDate?, source: IvyTask.Source?) -> IvyTask {
        guard let date else {
            return IvyTask(title: title, source: source)
        }
        return IvyTask(
            title: title,
            dueAt: date.isAllDay ? Calendar.current.startOfDay(for: date.date) : date.date,
            isAllDay: date.isAllDay,
            source: source,
        )
    }

    // MARK: - Settings

    static var detectDatesTitle: String {
        IvyLocalizedString("MESSAGE_DETECTION_DATES", comment: "Switch in the chat settings that underlines dates and times in messages.")
    }

    static var detectTasksTitle: String {
        IvyLocalizedString("MESSAGE_DETECTION_TASKS", comment: "Switch in the chat settings that underlines requests like “Can you…” in messages.")
    }

    static var footer: String {
        IvyLocalizedString("MESSAGE_DETECTION_FOOTER", comment: "Explains the switches that underline dates and requests in messages.")
    }
}

extension ConversationViewController {

    /// Offers the calendar and tasks for a date or a request underlined in a
    /// message. Returns false for anything else.
    func ivyDidTapDetectedItem(_ item: CVTextLabel.Item, interaction: TSInteraction) -> Bool {
        guard
            case .dataItem(let dataItem) = item,
            dataItem.dataType == .date || dataItem.dataType == .task,
            let message = interaction as? TSMessage,
            let text = message.body?.nilIfEmpty
        else {
            return false
        }
        let source = IvyMessageReference(message: message, thread: thread).map {
            IvyTask.Source(message: $0, quote: IvyTask.quote(fromMessageText: text))
        }
        let snippetRange = (text as NSString).range(of: dataItem.snippet)
        let otherRanges = snippetRange.location == NSNotFound ? [] : [snippetRange]

        let sheetTitle: String
        let title: String
        let date: IvyDetectedDate?
        if dataItem.dataType == .date {
            guard let detected = IvyDetectedItemsUI.date(for: dataItem.snippet, in: text) else {
                return false
            }
            sheetTitle = IvyDetectedItemsUI.dateText(detected)
            title = IvyTaskPhrases.phrases(in: text, avoiding: otherRanges).first?.title ?? IvyTask.title(fromMessageText: text)
            date = detected
        } else {
            title = IvyTaskPhrases.title(fromPhrase: dataItem.snippet) ?? dataItem.snippet
            sheetTitle = title
            date = IvyDateDetection.firstUpcomingDate(in: text)
        }

        let actionSheet = ActionSheetController(title: sheetTitle)
        let addEvent = ActionSheetAction(title: IvyCalendarUI.addEventTitle, style: .default) { [weak self] _ in
            guard let date else { return }
            self?.ivyPresentEventEditor(IvyEvent.draft(from: date, title: title, source: source), isNew: true)
        }
        let addTask = ActionSheetAction(title: IvyTaskUI.addTaskTitle, style: .default) { [weak self] _ in
            self?.ivyPresentTaskEditor(IvyDetectedItemsUI.task(title: title, date: date, source: source), isNew: true)
        }
        if dataItem.dataType == .date {
            actionSheet.addAction(addEvent)
            actionSheet.addAction(addTask)
        } else {
            actionSheet.addAction(addTask)
            if date != nil {
                actionSheet.addAction(addEvent)
            }
        }
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.copyButton, style: .default) { _ in
            UIPasteboard.general.string = dataItem.snippet
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
        return true
    }
}

extension ChatsSettingsViewController {

    /// "Detect Dates" and "Detect Tasks", in the chat settings.
    func ivyAddDetectionSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.footerTitle = IvyDetectedItemsUI.footer
        section.add(.switch(
            withText: IvyDetectedItemsUI.detectDatesTitle,
            isOn: { IvyMessageDetection.detectsDates },
            actionBlock: { uiSwitch in
                IvyMessageDetection.detectsDates = uiSwitch.isOn
            },
        ))
        section.add(.switch(
            withText: IvyDetectedItemsUI.detectTasksTitle,
            isOn: { IvyMessageDetection.detectsTasks },
            actionBlock: { uiSwitch in
                IvyMessageDetection.detectsTasks = uiSwitch.isOn
            },
        ))
        contents.add(section)
    }
}
