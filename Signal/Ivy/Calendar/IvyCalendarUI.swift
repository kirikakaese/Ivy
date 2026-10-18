//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers

enum IvyCalendarUI {

    static var calendarTitle: String {
        IvyLocalizedString("CALENDAR_TITLE", comment: "Title of the calendar.")
    }

    static var addEventTitle: String {
        IvyLocalizedString("EVENT_ADD_TO_CALENDAR", comment: "Action that makes a calendar event, for example from a message.")
    }

    static func title(for frequency: IvyRecurrence.Frequency?) -> String {
        switch frequency {
        case nil:
            return IvyLocalizedString("EVENT_REPEAT_NEVER", comment: "Event repeat option: does not repeat.")
        case .daily:
            return IvyLocalizedString("EVENT_REPEAT_DAILY", comment: "Event repeat option: every day.")
        case .weekly:
            return IvyLocalizedString("EVENT_REPEAT_WEEKLY", comment: "Event repeat option: every week.")
        case .monthly:
            return IvyLocalizedString("EVENT_REPEAT_MONTHLY", comment: "Event repeat option: every month.")
        case .yearly:
            return IvyLocalizedString("EVENT_REPEAT_YEARLY", comment: "Event repeat option: every year.")
        }
    }

    /// The alert choices, in minutes before the start.
    static let alertChoices: [Int?] = [nil, 0, 5, 15, 30, 60, 120, 1440, 2880, 10_080]

    static func title(forAlert minutes: Int?) -> String {
        guard let minutes else {
            return IvyLocalizedString("EVENT_ALERT_NONE", comment: "Event alert option: no alert.")
        }
        if minutes == 0 {
            return IvyLocalizedString("EVENT_ALERT_AT_START", comment: "Event alert option: when the event starts.")
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = minutes % 1440 == 0 ? [.day, .weekOfMonth] : (minutes % 60 == 0 ? [.hour] : [.minute])
        let amount = formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)"
        return String.localizedStringWithFormat(
            IvyLocalizedString("EVENT_ALERT_BEFORE_FORMAT", comment: "Event alert option. Embeds {{ an amount of time, e.g. 15 minutes }}."),
            amount,
        )
    }

    /// "14:00 – 15:30", "All day" or, for a task or reminder, its time.
    static func timeText(for item: IvyCalendarItem) -> String {
        if item.isAllDay {
            return IvyLocalizedString("EVENT_ALL_DAY", comment: "Shown instead of a time for an all-day event.")
        }
        let start = DateFormatter.localizedString(from: item.start, dateStyle: .none, timeStyle: .short)
        guard item.end > item.start else {
            return start
        }
        let end = DateFormatter.localizedString(from: item.end, dateStyle: .none, timeStyle: .short)
        return start + " – " + end
    }

    static func dayTitle(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }

    /// An event for a message: on the first date in its text, or tomorrow.
    static func event(from message: TSMessage, thread: TSThread) -> IvyEvent {
        let text = message.body ?? ""
        let source = IvyMessageReference(message: message, thread: thread).map {
            IvyTask.Source(message: $0, quote: IvyTask.quote(fromMessageText: text))
        }
        let title = IvyTask.title(fromMessageText: text)
        if let detected = IvyDateDetection.firstUpcomingDate(in: text) {
            return IvyEvent.draft(from: detected, title: title, source: source)
        }
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return IvyEvent(title: title, startAt: start, endAt: start.addingTimeInterval(60 * 60), source: source)
    }

    // MARK: - Files

    /// Writes events to a temporary `.ics` file named after the first one.
    static func writeCalendarFile(_ events: [IvyEvent], name: String? = nil) -> URL? {
        let fileName = (name ?? events.first?.title ?? calendarTitle)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((fileName.isEmpty ? calendarTitle : String(fileName.prefix(60))) + "." + IvyICS.fileExtension)
        do {
            try IvyICS.export(events).data(using: .utf8)?.write(to: url, options: .completeFileProtection)
            return url
        } catch {
            Logger.warn("Couldn't write a calendar file: \(error)")
            return nil
        }
    }

    static var calendarContentType: UTType {
        UTType(filenameExtension: IvyICS.fileExtension) ?? UTType(mimeType: IvyICS.mimeType) ?? .data
    }
}

extension UIViewController {

    func ivyPresentEventEditor(_ event: IvyEvent, isNew: Bool) {
        let editor = IvyEventEditorViewController(event: event, isNew: isNew)
        presentFormSheet(OWSNavigationController(rootViewController: editor), animated: true)
    }

    func ivyPresentCalendar() {
        presentFormSheet(OWSNavigationController(rootViewController: IvyCalendarViewController()), animated: true)
    }

    /// Saves events as an `.ics` file wherever the user chooses.
    func ivyExportCalendarFile(_ events: [IvyEvent], name: String? = nil) {
        guard let url = IvyCalendarUI.writeCalendarFile(events, name: name) else {
            OWSActionSheets.showErrorAlert(message: IvyLocalizedString("CALENDAR_EXPORT_FAILED", comment: "Shown when a calendar file couldn't be written."))
            return
        }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        present(picker, animated: true)
    }

    /// Sends an event as an `.ics` file in a chat the user picks. People on
    /// other Signal apps receive a normal file.
    func ivySendEventToChat(_ event: IvyEvent) {
        let chooser = IvyChatChooserViewController(preferredChat: event.source?.message.chat) { thread in
            guard let url = IvyCalendarUI.writeCalendarFile([event]) else {
                return
            }
            let root = CurrentAppContext().frontmostViewController()?.view.window?.rootViewController
            let open = {
                SignalApp.shared.presentConversationForThread(threadUniqueId: thread.uniqueId, animated: false)
                DispatchQueue.main.async {
                    SignalApp.shared.conversationSplitViewController?.selectedConversationViewController?.ivyAttachFile(url: url)
                }
            }
            if let root, root.presentedViewController != nil {
                root.dismiss(animated: true, completion: open)
            } else {
                open()
            }
        }
        presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
    }
}

// MARK: - Conversation

extension ConversationViewController {

    /// "Add to Calendar" in a message's context menu, prefilled with the
    /// first date in the message's text.
    func ivyAddEventContextMenuAction(interaction: TSInteraction, thread: TSThread) -> ContextMenuAction? {
        guard let message = interaction as? TSMessage else {
            return nil
        }
        return ContextMenuAction(
            title: IvyCalendarUI.addEventTitle,
            image: UIImage(systemName: "calendar.badge.plus"),
        ) { [weak self] _ in
            self?.ivyPresentEventEditor(IvyCalendarUI.event(from: message, thread: thread), isNew: true)
        }
    }

    /// Opens the attachment approval for a file, like picking it from Files.
    func ivyAttachFile(url: URL) {
        let dataSource = DataSourcePath(fileUrl: url, ownership: .owned)
        dataSource.sourceFilename = url.lastPathComponent
        let attachmentLimits = OutgoingAttachmentLimits.currentLimits()
        do {
            let attachment = try PreviewableAttachment.buildAttachment(
                dataSource: dataSource,
                dataUTI: IvyCalendarUI.calendarContentType.identifier,
                attachmentLimits: attachmentLimits,
            )
            showApprovalDialog(forAttachments: [attachment], attachmentLimits: attachmentLimits)
        } catch {
            showErrorAlert(attachmentError: error as? SignalAttachmentError)
        }
    }
}

// MARK: - Notifications

enum IvyEventActionHandler {

    /// Opens the event of an alert. Returns false for other notifications.
    @MainActor
    static func handle(_ response: UNNotificationResponse) -> Bool {
        guard let eventId = IvyEventNotifications.eventId(of: response.notification.request) else {
            return false
        }
        if let event = IvyEventManager.shared.event(id: eventId), let frontmost = CurrentAppContext().frontmostViewController() {
            frontmost.ivyPresentEventEditor(event, isNew: false)
        }
        return true
    }
}

// MARK: - Choosing a chat

/// The user's chats, most recent first, to send something to one of them.
final class IvyChatChooserViewController: OWSTableViewController2 {

    private let preferredChat: IvyChatReference?
    private let onChoose: (TSThread) -> Void

    init(preferredChat: IvyChatReference?, onChoose: @escaping (TSThread) -> Void) {
        self.preferredChat = preferredChat
        self.onChoose = onChoose
        super.init()
    }

    /// Chats shown at most.
    private static let maxChats = 100

    override func viewDidLoad() {
        super.viewDidLoad()
        title = title ?? IvyLocalizedString("EVENT_SEND_TO_CHAT", comment: "Action that sends an event as a calendar file in a chat.")
        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)

        let rows: [(thread: TSThread, name: String)] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            var rows = [(thread: TSThread, name: String)]()
            ThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: tx) { thread in
                guard rows.count < Self.maxChats else { return }
                rows.append((thread, SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)))
            }
            return rows
        }
        let ordered = rows.sorted { lhs, rhs in
            let lhsPreferred = preferredChat != nil && IvyChatReference(thread: lhs.thread) == preferredChat
            let rhsPreferred = preferredChat != nil && IvyChatReference(thread: rhs.thread) == preferredChat
            return lhsPreferred && !rhsPreferred
        }

        let section = OWSTableSection()
        for row in ordered {
            section.add(.disclosureItem(withText: row.name) { [weak self] in
                guard let self else { return }
                let onChoose = self.onChoose
                dismiss(animated: true) {
                    onChoose(row.thread)
                }
            })
        }
        let contents = OWSTableContents(title: title)
        contents.add(section)
        self.contents = contents
    }
}
