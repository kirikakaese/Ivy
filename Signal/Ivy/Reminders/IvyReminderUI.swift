//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - Choosing a time

enum IvyReminderUI {

    static func title(for preset: IvyReminder.Preset) -> String {
        switch preset {
        case .twentyMinutes:
            return IvyLocalizedString("REMINDER_PRESET_20_MINUTES", comment: "Reminder option: in 20 minutes.")
        case .oneHour:
            return IvyLocalizedString("REMINDER_PRESET_1_HOUR", comment: "Reminder option: in one hour.")
        case .threeHours:
            return IvyLocalizedString("REMINDER_PRESET_3_HOURS", comment: "Reminder option: in three hours.")
        case .laterToday:
            return IvyLocalizedString("REMINDER_PRESET_LATER_TODAY", comment: "Reminder option: later today.")
        case .tonight:
            return IvyLocalizedString("REMINDER_PRESET_TONIGHT", comment: "Reminder option: tonight at 8 pm.")
        case .tomorrowMorning:
            return IvyLocalizedString("REMINDER_PRESET_TOMORROW", comment: "Reminder option: tomorrow morning.")
        case .nextWeek:
            return IvyLocalizedString("REMINDER_PRESET_NEXT_WEEK", comment: "Reminder option: next Monday morning.")
        }
    }

    static var remindMeTitle: String {
        IvyLocalizedString("REMINDER_REMIND_ME", comment: "Action that sets a reminder for a message or a chat.")
    }

    static var customTitle: String {
        IvyLocalizedString("REMINDER_PRESET_CUSTOM", comment: "Reminder option: choose a date and time.")
    }

    static func dueDateText(_ date: Date) -> String {
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    /// The presets that apply now, with their due dates.
    static func availablePresets(now: Date = Date()) -> [(IvyReminder.Preset, Date)] {
        return IvyReminder.Preset.allCases.compactMap { preset in
            preset.dueDate(from: now).map { (preset, $0) }
        }
    }

    static func add(chat: IvyChatReference, message: IvyMessageReference?, dueAt: Date, repeats: IvyReminder.Repeat = .never) {
        IvyReminderManager.shared.add(IvyReminder(chat: chat, message: message, dueAt: dueAt, repeats: repeats))
        let toast = String.localizedStringWithFormat(
            IvyLocalizedString("REMINDER_SET_FORMAT", comment: "Shown after setting a reminder. Embeds {{ the date and time }}."),
            dueDateText(dueAt),
        )
        CurrentAppContext().frontmostViewController()?.presentToast(text: toast)
    }

    /// The menu of presets for the chat list's context menu.
    static func menu(chat: IvyChatReference, from viewController: UIViewController) -> UIMenu {
        var children: [UIMenuElement] = availablePresets().map { preset, date in
            UIAction(title: title(for: preset), subtitle: dueDateText(date)) { _ in
                add(chat: chat, message: nil, dueAt: date)
            }
        }
        children.append(UIAction(title: customTitle, image: UIImage(systemName: "calendar")) { [weak viewController] _ in
            viewController?.ivyPresentReminderDatePicker(chat: chat, message: nil)
        })
        return UIMenu(title: remindMeTitle, image: UIImage(systemName: "bell.badge"), children: children)
    }
}

extension UIViewController {

    /// An action sheet with the reminder presets.
    func ivyPresentRemindMe(chat: IvyChatReference, message: IvyMessageReference?) {
        let sheet = ActionSheetController(title: IvyReminderUI.remindMeTitle)
        for (preset, date) in IvyReminderUI.availablePresets() {
            sheet.addAction(ActionSheetAction(title: IvyReminderUI.title(for: preset), style: .default) { _ in
                IvyReminderUI.add(chat: chat, message: message, dueAt: date)
            })
        }
        sheet.addAction(ActionSheetAction(title: IvyReminderUI.customTitle, style: .default) { [weak self] _ in
            self?.ivyPresentReminderDatePicker(chat: chat, message: message)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    func ivyPresentReminderDatePicker(chat: IvyChatReference, message: IvyMessageReference?) {
        let picker = IvyReminderDatePickerViewController { date, repeats in
            IvyReminderUI.add(chat: chat, message: message, dueAt: date, repeats: repeats)
        }
        presentFormSheet(OWSNavigationController(rootViewController: picker), animated: true)
    }
}

/// Chooses a date and time, and whether the reminder repeats.
final class IvyReminderDatePickerViewController: UIViewController {

    private let datePicker = UIDatePicker()
    private let repeatControl = UISegmentedControl()
    private let onDone: (Date, IvyReminder.Repeat) -> Void

    init(initialDate: Date? = nil, onDone: @escaping (Date, IvyReminder.Repeat) -> Void) {
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
        datePicker.date = initialDate ?? IvyReminder.Preset.tomorrowMorning.dueDate(from: Date()) ?? Date().addingTimeInterval(3600)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyReminderUI.remindMeTitle
        view.backgroundColor = .Signal.groupedBackground
        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.done() }

        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .inline
        datePicker.minimumDate = Date()

        let repeatLabel = UILabel()
        repeatLabel.text = IvyLocalizedString("REMINDER_REPEAT", comment: "Label of the option that makes a reminder repeat.")
        repeatLabel.font = .dynamicTypeSubheadline
        repeatLabel.textColor = .Signal.secondaryLabel

        for (index, option) in IvyReminder.Repeat.allCases.enumerated() {
            repeatControl.insertSegment(withTitle: Self.title(for: option), at: index, animated: false)
        }
        repeatControl.selectedSegmentIndex = 0

        let stack = UIStackView(arrangedSubviews: [datePicker, repeatLabel, repeatControl])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func done() {
        let repeats = IvyReminder.Repeat.allCases[max(repeatControl.selectedSegmentIndex, 0)]
        let date = max(datePicker.date, Date().addingTimeInterval(60))
        dismiss(animated: true) { [onDone] in
            onDone(date, repeats)
        }
    }

    static func title(for option: IvyReminder.Repeat) -> String {
        switch option {
        case .never:
            return IvyLocalizedString("REMINDER_REPEAT_NEVER", comment: "Reminder repeat option: does not repeat.")
        case .daily:
            return IvyLocalizedString("REMINDER_REPEAT_DAILY", comment: "Reminder repeat option: every day.")
        case .weekly:
            return IvyLocalizedString("REMINDER_REPEAT_WEEKLY", comment: "Reminder repeat option: every week.")
        case .monthly:
            return IvyLocalizedString("REMINDER_REPEAT_MONTHLY", comment: "Reminder repeat option: every month.")
        }
    }
}

// MARK: - Conversation

extension ConversationViewController {

    /// "Remind Me" in a message's context menu.
    func ivyRemindMeContextMenuAction(interaction: TSInteraction, thread: TSThread) -> ContextMenuAction? {
        guard let message = interaction as? TSMessage, let reference = IvyMessageReference(message: message, thread: thread) else {
            return nil
        }
        return ContextMenuAction(
            title: IvyReminderUI.remindMeTitle,
            image: UIImage(systemName: "bell.badge"),
        ) { [weak self] _ in
            self?.ivyPresentRemindMe(chat: reference.chat, message: reference)
        }
    }
}

// MARK: - Notifications

enum IvyReminderActionHandler {

    /// Handles a reminder notification. Returns false for other
    /// notifications.
    @MainActor
    static func handle(_ response: UNNotificationResponse) -> Bool {
        guard let reminderId = IvyReminderNotifications.reminderId(of: response.notification.request) else {
            return false
        }
        let manager = IvyReminderManager.shared
        switch response.actionIdentifier {
        case IvyReminderNotifications.Action.snoozeOneHour.rawValue:
            manager.snoozeOneHour(id: reminderId)
        case IvyReminderNotifications.Action.tomorrow.rawValue:
            manager.remindTomorrow(id: reminderId)
        case IvyReminderNotifications.Action.done.rawValue:
            manager.markDone(id: reminderId)
        default:
            open(reminderId: reminderId)
        }
        return true
    }

    /// Opens the reminder's message or chat and marks the reminder done.
    @MainActor
    static func open(reminderId: String) {
        guard let reminder = IvyReminderStore.reminder(id: reminderId, store: IvyData.shared?.store) else {
            return
        }
        let (threadId, messageId) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (reminder.chat.thread(tx: tx)?.uniqueId, reminder.message?.message(tx: tx)?.uniqueId)
        }
        if reminder.isDue(at: Date()) {
            IvyReminderManager.shared.markDone(id: reminderId)
        }
        guard let threadId else {
            return
        }
        if let messageId {
            SignalApp.shared.presentConversationForThread(threadUniqueId: threadId, focusMessageId: messageId, animated: true)
        } else {
            SignalApp.shared.presentConversationAndScrollToFirstUnreadMessage(threadUniqueId: threadId, animated: true)
        }
    }
}
