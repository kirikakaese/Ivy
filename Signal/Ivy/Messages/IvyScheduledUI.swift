//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum IvyScheduledUI {

    static var title: String {
        IvyLocalizedString("SCHEDULED_TITLE", comment: "Title of the list of messages scheduled to be sent later.")
    }

    static var sendLaterTitle: String {
        IvyLocalizedString("SCHEDULED_SEND_LATER", comment: "Menu of the send button that sends the message at a later time.")
    }

    /// "Today, 18:00".
    static func sendTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor
    static func schedule(_ body: MessageBody, in thread: TSThread, at date: Date) {
        IvyScheduledSender.shared.schedule(body, in: thread, at: date)
        let toast = String.localizedStringWithFormat(
            IvyLocalizedString("SCHEDULED_SET_FORMAT", comment: "Shown after scheduling a message. Embeds {{ the date and time }}."),
            sendTimeText(date),
        )
        CurrentAppContext().frontmostViewController()?.presentToast(text: toast)
    }

    @MainActor
    static func pending(in chat: IvyChatReference? = nil) -> [IvyScheduledMessage] {
        IvyScheduledStore.pending(store: IvyData.shared?.store).filter { chat == nil || $0.chat == chat }
    }
}

// MARK: - Send button

extension ConversationInputToolbar {

    /// Holding or right-clicking the send button offers to send the message
    /// later: the reminder presets and a custom time.
    func ivySendLaterMenu() -> UIMenu {
        UIMenu(title: IvyScheduledUI.sendLaterTitle, children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }
                var children: [UIMenuElement] = IvyReminderUI.availablePresets().map { preset, date in
                    UIAction(title: IvyReminderUI.title(for: preset), subtitle: IvyScheduledUI.sendTimeText(date)) { [weak self] _ in
                        self?.ivySendLater(at: date)
                    }
                }
                children.append(UIAction(title: IvyReminderUI.customTitle, image: UIImage(systemName: "calendar")) { [weak self] _ in
                    self?.ivyChooseSendTime()
                })
                completion(ivyHasTextToSchedule ? children : [])
            },
        ])
    }

    private var ivyHasTextToSchedule: Bool {
        guard let text = messageBodyForSending?.text else {
            return false
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var ivyConversationViewController: ConversationViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let conversation = current as? ConversationViewController {
                return conversation
            }
            responder = current.next
        }
        return nil
    }

    private func ivyChooseSendTime() {
        guard let conversation = ivyConversationViewController else {
            return
        }
        let picker = IvyReminderDatePickerViewController(
            initialDate: Date().addingTimeInterval(60 * 60),
            title: IvyScheduledUI.sendLaterTitle,
            showsRepeat: false,
        ) { [weak self] date, _ in
            self?.ivySendLater(at: date)
        }
        conversation.presentFormSheet(OWSNavigationController(rootViewController: picker), animated: true)
    }

    private func ivySendLater(at date: Date) {
        guard ivyHasTextToSchedule, let body = messageBodyForSending, let thread = ivyConversationViewController?.thread else {
            return
        }
        IvyScheduledUI.schedule(body, in: thread, at: date)
        clearTextMessage(animated: true)
    }
}

// MARK: - Chat settings

extension ConversationSettingsViewController {

    /// "Scheduled Messages", when the chat has some.
    func ivyAddScheduledItem(to section: OWSTableSection) {
        guard let chat = IvyChatReference(thread: thread) else {
            return
        }
        let count = IvyScheduledUI.pending(in: chat).count
        guard count > 0 else {
            return
        }
        section.add(.disclosureItem(
            icon: .contextMenuMessage,
            withText: IvyScheduledUI.title,
            accessoryText: count.formatted(),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyScheduledMessagesViewController(chat: chat), animated: true)
            },
        ))
    }
}

// MARK: - List

/// Scheduled messages that aren't sent yet, of one chat or of all chats.
final class IvyScheduledMessagesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let chat: IvyChatReference?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var messages: [IvyScheduledMessage] = []
    private var chatNames: [IvyChatReference: String] = [:]

    init(chat: IvyChatReference? = nil) {
        self.chat = chat
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyScheduledUI.title
        view.backgroundColor = .Signal.groupedBackground
        if navigationController?.viewControllers.first === self, navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "message")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: IvyScheduledSender.scheduledDidChange, object: nil)
        reload()
    }

    @objc
    private func reload() {
        messages = IvyScheduledUI.pending(in: chat)
        chatNames = SSKEnvironment.shared.databaseStorageRef.read { tx in
            var names = [IvyChatReference: String]()
            for message in messages where names[message.chat] == nil {
                if let thread = message.chat.thread(tx: tx) {
                    names[message.chat] = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                }
            }
            return names
        }
        tableView.backgroundView = messages.isEmpty ? emptyView() : nil
        tableView.reloadData()
    }

    private func emptyView() -> UIView {
        let label = UILabel()
        label.text = IvyLocalizedString("SCHEDULED_EMPTY", comment: "Shown in the list of scheduled messages when there are none.")
        label.font = .dynamicTypeBody
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        let container = UIView()
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath)
        let message = messages[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = message.previewText
        content.textProperties.numberOfLines = 3
        var detail = IvyScheduledUI.sendTimeText(message.sendAt)
        if chat == nil, let name = chatNames[message.chat] {
            detail = name + " · " + detail
        }
        content.secondaryText = detail
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.image = UIImage(systemName: "clock")
        content.imageProperties.tintColor = .Signal.accent
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }

    private func actions(for message: IvyScheduledMessage) -> [UIMenuElement] {
        [
            UIAction(
                title: IvyLocalizedString("SCHEDULED_SEND_NOW", comment: "Action that sends a scheduled message right away."),
                image: UIImage(systemName: "paperplane"),
            ) { _ in IvyScheduledSender.shared.sendNow(id: message.id) },
            UIAction(
                title: IvyLocalizedString("SCHEDULED_CHANGE_TIME", comment: "Action that changes when a scheduled message is sent."),
                image: UIImage(systemName: "clock"),
            ) { [weak self] _ in self?.changeTime(of: message) },
            UIAction(title: CommonStrings.deleteButton, image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                IvyScheduledSender.shared.delete(id: message.id)
            },
        ]
    }

    private func changeTime(of message: IvyScheduledMessage) {
        let picker = IvyReminderDatePickerViewController(
            initialDate: message.sendAt,
            title: IvyScheduledUI.sendLaterTitle,
            showsRepeat: false,
        ) { date, _ in
            IvyScheduledSender.shared.reschedule(id: message.id, to: date)
        }
        presentFormSheet(OWSNavigationController(rootViewController: picker), animated: true)
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let message = messages[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: self?.actions(for: message) ?? [])
        })
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let message = messages[indexPath.row]
        let sheet = ActionSheetController(title: message.previewText)
        sheet.addAction(ActionSheetAction(title: IvyLocalizedString("SCHEDULED_SEND_NOW", comment: "Action that sends a scheduled message right away.")) { _ in
            IvyScheduledSender.shared.sendNow(id: message.id)
        })
        sheet.addAction(ActionSheetAction(title: IvyLocalizedString("SCHEDULED_CHANGE_TIME", comment: "Action that changes when a scheduled message is sent.")) { [weak self] _ in
            self?.changeTime(of: message)
        })
        sheet.addAction(ActionSheetAction(title: CommonStrings.deleteButton, style: .destructive) { _ in
            IvyScheduledSender.shared.delete(id: message.id)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }
}
