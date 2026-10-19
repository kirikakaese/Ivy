//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// What the duress passcode opens: a chat list with a few made-up chats
/// that live only in memory and never send anything. The "Notes" chat holds
/// a button that deletes all Ivy data on this device. Ivy itself stays
/// locked behind it; leaving the app returns to the passcode screen.
@MainActor
enum IvyDecoy {

    struct Message {
        let text: String
        let isOutgoing: Bool
    }

    final class Chat {
        let name: String
        let color: UIColor
        var messages: [Message]
        /// The chat with the button that deletes all data.
        let hasWipeButton: Bool

        init(name: String, color: UIColor, messages: [Message], hasWipeButton: Bool = false) {
            self.name = name
            self.color = color
            self.messages = messages
            self.hasWipeButton = hasWipeButton
        }
    }

    static func present(over viewController: UIViewController) {
        let navigationController = IvyDecoyNavigationController(rootViewController: IvyDecoyChatListViewController(chats: makeChats()))
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.modalPresentationStyle = .fullScreen
        viewController.present(navigationController, animated: false)
    }

    static func makeChats() -> [Chat] {
        func incoming(_ text: String) -> Message { Message(text: text, isOutgoing: false) }
        func outgoing(_ text: String) -> Message { Message(text: text, isOutgoing: true) }
        return [
            Chat(name: IvyLocalizedString("DECOY_CHAT_MOM", comment: "Name of a made-up chat in the decoy mode."), color: .systemPink, messages: [
                incoming(IvyLocalizedString("DECOY_MOM_1", comment: "A made-up message in the decoy mode, from a mother.")),
                outgoing(IvyLocalizedString("DECOY_MOM_2", comment: "A made-up reply to a mother in the decoy mode.")),
                incoming(IvyLocalizedString("DECOY_MOM_3", comment: "A made-up message in the decoy mode, from a mother.")),
            ]),
            Chat(name: IvyLocalizedString("DECOY_CHAT_FRIEND", comment: "Name of a made-up chat in the decoy mode."), color: .systemBlue, messages: [
                incoming(IvyLocalizedString("DECOY_FRIEND_1", comment: "A made-up message in the decoy mode, from a friend.")),
                outgoing(IvyLocalizedString("DECOY_FRIEND_2", comment: "A made-up reply to a friend in the decoy mode.")),
            ]),
            Chat(name: IvyLocalizedString("DECOY_CHAT_GROUP", comment: "Name of a made-up group chat in the decoy mode."), color: .systemOrange, messages: [
                incoming(IvyLocalizedString("DECOY_GROUP_1", comment: "A made-up message in a group chat in the decoy mode.")),
                incoming(IvyLocalizedString("DECOY_GROUP_2", comment: "A made-up message in a group chat in the decoy mode.")),
                outgoing(IvyLocalizedString("DECOY_GROUP_3", comment: "A made-up reply in a group chat in the decoy mode.")),
            ]),
            Chat(name: IvyLocalizedString("DECOY_CHAT_NOTES", comment: "Name of the made-up notes chat in the decoy mode, which holds the button that deletes all data."), color: .systemGreen, messages: [
                outgoing(IvyLocalizedString("DECOY_NOTES_1", comment: "A made-up note to self in the decoy mode.")),
            ], hasWipeButton: true),
        ]
    }

    static func confirmWipe(from viewController: UIViewController) {
        let sheet = ActionSheetController(
            title: IvyLocalizedString("DECOY_WIPE_CONFIRM_TITLE", comment: "Title of the confirmation before deleting all data from the decoy mode."),
            message: IvyLocalizedString("DECOY_WIPE_CONFIRM_MESSAGE", comment: "Explains that deleting all data can't be undone."),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("DECOY_WIPE", comment: "Button in the decoy mode that deletes all data on this device."),
            style: .destructive,
        ) { _ in
            Logger.warn("Deleting all data from the decoy mode.")
            SignalApp.shared.resetAppDataAndExit(keyFetcher: SSKEnvironment.shared.databaseStorageRef.keyFetcher)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        viewController.presentActionSheet(sheet)
    }
}

/// Closes the decoy mode when Ivy leaves the screen, back to the passcode.
private final class IvyDecoyNavigationController: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil,
        )
    }

    @objc
    private func didEnterBackground() {
        dismiss(animated: false)
    }
}

// MARK: - Chat list

private final class IvyDecoyChatListViewController: UITableViewController {

    private let chats: [IvyDecoy.Chat]

    init(chats: [IvyDecoy.Chat]) {
        self.chats = chats
        super.init(style: .plain)
        title = IvyLocalizedString("DECOY_CHATS_TITLE", comment: "Title of the chat list in the decoy mode.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .Signal.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chat")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chats.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let chat = chats[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = chat.name
        content.textProperties.font = .dynamicTypeHeadline
        content.secondaryText = chat.messages.last?.text
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: "person.crop.circle.fill")
        content.imageProperties.tintColor = chat.color
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
        content.imageToTextPadding = 12
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        cell.contentConfiguration = content
        cell.backgroundColor = .Signal.background
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(IvyDecoyChatViewController(chat: chats[indexPath.row]), animated: true)
    }
}

// MARK: - Chat

private final class IvyDecoyChatViewController: UIViewController, UITableViewDataSource, UITextFieldDelegate {

    private let chat: IvyDecoy.Chat
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let field = UITextField()

    init(chat: IvyDecoy.Chat) {
        self.chat = chat
        super.init(nibName: nil, bundle: nil)
        title = chat.name
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .Signal.background

        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .Signal.background
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.register(IvyDecoyBubbleCell.self, forCellReuseIdentifier: "bubble")
        if chat.hasWipeButton {
            tableView.tableFooterView = wipeFooter()
        }

        field.placeholder = IvyLocalizedString("DECOY_MESSAGE_PLACEHOLDER", comment: "Placeholder of the message field in the decoy mode.")
        field.borderStyle = .roundedRect
        field.returnKeyType = .send
        field.delegate = self

        let stack = UIStackView(arrangedSubviews: [tableView, field])
        stack.axis = .vertical
        stack.spacing = 8
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
        ])
    }

    private func wipeFooter() -> UIView {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = IvyLocalizedString("DECOY_WIPE", comment: "Button in the decoy mode that deletes all data on this device.")
        configuration.baseForegroundColor = .Signal.red
        configuration.baseBackgroundColor = .Signal.red
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            guard let self else {
                return
            }
            IvyDecoy.confirmWipe(from: self)
        })
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 76))
        footer.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }
        // Stays on the screen only; nothing is sent.
        chat.messages.append(IvyDecoy.Message(text: text, isOutgoing: true))
        textField.text = nil
        tableView.reloadData()
        tableView.scrollToRow(at: IndexPath(row: chat.messages.count - 1, section: 0), at: .bottom, animated: true)
        return false
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chat.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bubble", for: indexPath)
        (cell as? IvyDecoyBubbleCell)?.configure(with: chat.messages[indexPath.row])
        return cell
    }
}

private final class IvyDecoyBubbleCell: UITableViewCell {

    private let bubble = UIView()
    private let label = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        bubble.layer.cornerRadius = 18
        label.numberOfLines = 0
        label.font = .dynamicTypeBody
        contentView.addSubview(bubble)
        bubble.addSubview(label)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with message: IvyDecoy.Message) {
        label.text = message.text
        bubble.backgroundColor = message.isOutgoing ? .Signal.accent : .Signal.secondaryBackground
        label.textColor = message.isOutgoing ? .white : .Signal.label
        leading.isActive = !message.isOutgoing
        trailing.isActive = message.isOutgoing
    }
}
