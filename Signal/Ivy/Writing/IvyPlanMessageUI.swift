//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

extension UIViewController {

    /// Writes a message for a chat and a time, which Ivy sends then (see
    /// scheduled messages). `onScheduled` runs after it was scheduled.
    func ivyPresentPlanMessage(chat: IvyChatReference?, text: String = "", sendAt: Date, onScheduled: (() -> Void)? = nil) {
        let composer = IvyPlanMessageViewController(chat: chat, text: text, sendAt: sendAt, onScheduled: onScheduled)
        presentFormSheet(OWSNavigationController(rootViewController: composer), animated: true)
    }
}

enum IvyPlanMessageUI {

    static var planTitle: String {
        IvyLocalizedString("PLAN_MESSAGE", comment: "Action that writes a message to be sent at a chosen time from the calendar or a draft.")
    }

    /// The next full hour on `day` when it is today, otherwise 9:00 that day.
    static func suggestedTime(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            return calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(60 * 60)
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}

/// A chat, a text and a time: schedules the message.
final class IvyPlanMessageViewController: UIViewController {

    private var chat: IvyChatReference?
    private let onScheduled: (() -> Void)?
    private let chatButton = UIButton(type: .system)
    private let textView = UITextView()
    private let datePicker = UIDatePicker()

    init(chat: IvyChatReference?, text: String, sendAt: Date, onScheduled: (() -> Void)?) {
        self.chat = chat
        self.onScheduled = onScheduled
        super.init(nibName: nil, bundle: nil)
        textView.text = text
        datePicker.date = max(sendAt, Date().addingTimeInterval(60))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyPlanMessageUI.planTitle
        view.backgroundColor = .Signal.groupedBackground
        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: IvyLocalizedString("PLAN_MESSAGE_SCHEDULE", comment: "Button that schedules a planned message."),
            primaryAction: UIAction { [weak self] _ in self?.schedule() },
        )

        var chatConfiguration = UIButton.Configuration.gray()
        chatConfiguration.image = UIImage(systemName: "bubble.left.and.bubble.right")
        chatConfiguration.imagePadding = 8
        chatConfiguration.cornerStyle = .large
        chatConfiguration.baseForegroundColor = .Signal.label
        chatButton.configuration = chatConfiguration
        chatButton.contentHorizontalAlignment = .leading
        chatButton.addAction(UIAction { [weak self] _ in self?.chooseChat() }, for: .primaryActionTriggered)
        updateChatButton()

        textView.font = .dynamicTypeBody
        textView.adjustsFontForContentSizeCategory = true
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.backgroundColor = .Signal.secondaryGroupedBackground

        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .compact
        datePicker.minimumDate = Date()
        let timeLabel = UILabel()
        timeLabel.text = IvyLocalizedString("PLAN_MESSAGE_SEND_AT", comment: "Label of the time a planned message is sent.")
        timeLabel.font = .dynamicTypeBody
        timeLabel.textColor = .Signal.label
        let timeRow = UIStackView(arrangedSubviews: [timeLabel, UIView(), datePicker])
        timeRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [chatButton, textView, timeRow])
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            textView.heightAnchor.constraint(equalToConstant: 160),
            chatButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if chat != nil {
            textView.becomeFirstResponder()
        }
    }

    private func updateChatButton() {
        let name = chat.flatMap { chat in
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                chat.thread(tx: tx).map { SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx) }
            }
        }
        chatButton.configuration?.title = name ?? IvyLocalizedString("PLAN_MESSAGE_CHOOSE_CHAT", comment: "Button that chooses the chat of a planned message.")
    }

    private func chooseChat() {
        let chooser = IvyChatChooserViewController(preferredChat: chat) { [weak self] thread in
            self?.chat = IvyChatReference(thread: thread)
            self?.updateChatButton()
        }
        chooser.title = IvyLocalizedString("PLAN_MESSAGE_CHOOSE_CHAT", comment: "Button that chooses the chat of a planned message.")
        presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
    }

    private func schedule() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !text.isEmpty,
            let chat,
            let thread = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in chat.thread(tx: tx) })
        else {
            presentToast(text: IvyLocalizedString("PLAN_MESSAGE_INCOMPLETE", comment: "Shown when a planned message has no chat or no text."))
            return
        }
        let date = max(datePicker.date, Date().addingTimeInterval(60))
        let onScheduled = self.onScheduled
        dismiss(animated: true) {
            IvyScheduledUI.schedule(MessageBody(text: text, ranges: .empty), in: thread, at: date)
            onScheduled?()
        }
    }
}
