//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Speech
import SignalServiceKit
import SignalUI

// MARK: - Message actions

extension ConversationViewController {

    /// "Star" or "Unstar" in a message's context menu.
    func ivyStarContextMenuAction(interaction: TSInteraction, thread: TSThread) -> ContextMenuAction? {
        guard let message = interaction as? TSMessage, let reference = IvyMessageReference(message: message, thread: thread) else {
            return nil
        }
        if IvyStarManager.shared.isStarred(message: message, thread: thread) {
            return ContextMenuAction(
                title: IvyLocalizedString("STAR_REMOVE", comment: "Action that removes the star from a message."),
                image: UIImage(systemName: "star.slash"),
            ) { _ in
                IvyStarManager.shared.unstar(reference)
            }
        }
        return ContextMenuAction(
            title: IvyLocalizedString("STAR_ADD", comment: "Action that stars a message, to find it again in the list of starred messages."),
            image: UIImage(systemName: "star"),
        ) { _ in
            IvyStarManager.shared.star(message, thread: thread)
        }
    }

    /// "Transcribe" in the context menu of a voice or audio message.
    func ivyTranscribeContextMenuAction(itemViewModel: CVItemViewModelImpl) -> ContextMenuAction? {
        guard let attachment = itemViewModel.audioAttachmentStream else {
            return nil
        }
        return ContextMenuAction(
            title: IvyLocalizedString("TRANSCRIBE", comment: "Action that turns a voice message into text, on the device."),
            image: UIImage(systemName: "text.quote"),
        ) { [weak self] _ in
            let viewController = IvyTranscriptViewController(
                attachment: attachment,
                message: Self.ivyMessageReference(itemViewModel: itemViewModel),
            )
            self?.presentFormSheet(OWSNavigationController(rootViewController: viewController), animated: true)
        }
    }

    /// "Make Task" for a voice note in Note to Self: transcribes it on the
    /// device, then opens the new task.
    func ivyVoiceNoteTaskContextMenuAction(itemViewModel: CVItemViewModelImpl, thread: TSThread) -> ContextMenuAction? {
        guard thread.isNoteToSelf, let attachment = itemViewModel.audioAttachmentStream else {
            return nil
        }
        return ContextMenuAction(
            title: IvyLocalizedString("VOICE_NOTE_MAKE_TASK", comment: "Action that turns a voice note into a task, transcribed on the device."),
            image: UIImage(systemName: "checklist"),
        ) { [weak self] _ in
            let viewController = IvyTranscriptViewController(
                attachment: attachment,
                message: Self.ivyMessageReference(itemViewModel: itemViewModel),
                makesTaskWhenDone: true,
            )
            self?.presentFormSheet(OWSNavigationController(rootViewController: viewController), animated: true)
        }
    }

    private static func ivyMessageReference(itemViewModel: CVItemViewModelImpl) -> IvyMessageReference? {
        guard let message = itemViewModel.interaction as? TSMessage else {
            return nil
        }
        return IvyMessageReference(message: message, thread: itemViewModel.thread)
    }
}

// MARK: - Starred messages

/// Starred messages from all chats, newest first.
final class IvyStarredViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    static var title: String {
        IvyLocalizedString("STARRED_TITLE", comment: "Title of the list of starred messages.")
    }

    private struct Row {
        let star: IvyStar
        let chatName: String
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [Row] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        view.backgroundColor = .Signal.groupedBackground
        if navigationController?.viewControllers.first === self, navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "star")
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: IvyStarManager.starsDidChange, object: nil)
        reload()
    }

    @objc
    private func reload() {
        let stars = IvyStarManager.shared.allStars()
        rows = SSKEnvironment.shared.databaseStorageRef.read { tx in
            stars.map { star in
                let name = star.message.chat.thread(tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                }
                return Row(star: star, chatName: name ?? "")
            }
        }
        tableView.backgroundView = rows.isEmpty ? Self.emptyView() : nil
        tableView.reloadData()
    }

    private static func emptyView() -> UIView {
        let label = UILabel()
        label.text = IvyLocalizedString("STARRED_EMPTY", comment: "Shown in the list of starred messages when there are none.")
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
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "star", for: indexPath)
        let row = rows[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.chatName
        content.secondaryText = row.star.quote.isEmpty
            ? IvyLocalizedString("REMINDER_BODY_MESSAGE", comment: "Body of a reminder notification about a message without text.")
            : row.star.quote
        content.secondaryTextProperties.numberOfLines = 3
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.image = UIImage(systemName: "star.fill")
        content.imageProperties.tintColor = .Signal.accent
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Self.open(rows[indexPath.row].star.message, from: self)
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let message = rows[indexPath.row].star.message
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [UIAction(
                title: IvyLocalizedString("STAR_REMOVE", comment: "Action that removes the star from a message."),
                image: UIImage(systemName: "star.slash"),
                attributes: .destructive,
            ) { _ in IvyStarManager.shared.unstar(message) }])
        })
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let message = rows[indexPath.row].star.message
        return UISwipeActionsConfiguration(actions: [UIContextualAction(
            style: .destructive,
            title: IvyLocalizedString("STAR_REMOVE", comment: "Action that removes the star from a message."),
        ) { _, _, completion in
            IvyStarManager.shared.unstar(message)
            completion(true)
        }])
    }

    /// Opens the chat at the starred message.
    static func open(_ message: IvyMessageReference, from viewController: UIViewController) {
        let (threadId, messageId) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (message.chat.thread(tx: tx)?.uniqueId, message.message(tx: tx)?.uniqueId)
        }
        guard let threadId else {
            return
        }
        let present = {
            if let messageId {
                SignalApp.shared.presentConversationForThread(threadUniqueId: threadId, focusMessageId: messageId, animated: true)
            } else {
                SignalApp.shared.presentConversationForThread(threadUniqueId: threadId, animated: true)
            }
        }
        if viewController.presentingViewController != nil || viewController.navigationController?.presentingViewController != nil {
            viewController.dismiss(animated: true, completion: present)
        } else {
            present()
        }
    }
}

// MARK: - Chat notes

extension ConversationSettingsViewController {

    /// "Note": the user's private note for this chat.
    func ivyAddChatNoteItem(to section: OWSTableSection) {
        guard let chat = IvyChatReference(thread: thread) else {
            return
        }
        let note = IvyChatNoteStore.note(for: chat, store: IvyData.shared?.store)
        let preview = note.split(separator: "\n").first.map(String.init)
        section.add(.disclosureItem(
            icon: .contextMenuEdit,
            withText: IvyChatNoteViewController.title,
            accessoryText: preview,
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyChatNoteViewController(chat: chat), animated: true)
            },
        ))
    }
}

/// Edits a chat's private note. Saved when leaving the screen.
final class IvyChatNoteViewController: UIViewController, UITextViewDelegate {

    static var title: String {
        IvyLocalizedString("CHAT_NOTE_TITLE", comment: "Title of a chat's private note.")
    }

    private let chat: IvyChatReference
    private let textView = UITextView()
    private let placeholder = UILabel()

    init(chat: IvyChatReference) {
        self.chat = chat
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        view.backgroundColor = .Signal.groupedBackground

        textView.font = .dynamicTypeBody
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .Signal.secondaryGroupedBackground
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.text = IvyChatNoteStore.note(for: chat, store: IvyData.shared?.store)
        textView.delegate = self

        placeholder.text = IvyLocalizedString("CHAT_NOTE_PLACEHOLDER", comment: "Shown in an empty chat note.")
        placeholder.font = .dynamicTypeBody
        placeholder.textColor = .Signal.tertiaryLabel
        placeholder.numberOfLines = 0
        placeholder.isHidden = !textView.text.isEmpty

        view.addSubview(textView)
        textView.addSubview(placeholder)
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 15),
            placeholder.widthAnchor.constraint(equalTo: textView.widthAnchor, constant: -30),
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        IvyChatNoteStore.save(textView.text, for: chat, store: IvyData.shared?.store)
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
    }
}

// MARK: - Transcripts

/// Turns a voice message into text with Apple's speech recognition, only on
/// the device: Ivy never sends the audio anywhere for this.
enum IvyTranscription {

    enum Failure: Error {
        case noAccess
        case notOnDevice
        case failed
    }

    /// Transcripts of this session, by attachment.
    @MainActor
    private static var cache = [Attachment.IDType: String]()

    @MainActor
    static func transcript(of attachment: AttachmentStream) async throws(Failure) -> String {
        if let cached = cache[attachment.attachment.id] {
            return cached
        }
        guard await requestAccess() else {
            throw .noAccess
        }
        guard let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.supportsOnDeviceRecognition else {
            throw .notOnDevice
        }
        let url: URL
        do {
            url = try attachment.makeDecryptedCopy(filename: nil)
        } catch {
            throw .failed
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        let text: String
        do {
            text = try await recognize(request, with: recognizer)
        } catch {
            Logger.warn("Transcription failed: \(error)")
            throw .failed
        }
        cache[attachment.attachment.id] = text
        return text
    }

    private static func requestAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default:
            return false
        }
    }

    /// Resumes once, with the final result or the first error.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var isDone = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isDone else { return false }
            isDone = true
            return true
        }
    }

    private static func recognize(_ request: SFSpeechURLRecognitionRequest, with recognizer: SFSpeechRecognizer) async throws -> String {
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if once.claim() { continuation.resume(throwing: error) }
                } else if let result, result.isFinal {
                    if once.claim() { continuation.resume(returning: result.bestTranscription.formattedString) }
                }
            }
        }
    }
}

/// Shows a voice message's transcript, transcribing it first.
final class IvyTranscriptViewController: UIViewController {

    private let attachment: AttachmentStream
    /// The voice note, for tasks made from the transcript.
    private let message: IvyMessageReference?
    private let makesTaskWhenDone: Bool
    private let textView = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()

    init(attachment: AttachmentStream, message: IvyMessageReference? = nil, makesTaskWhenDone: Bool = false) {
        self.attachment = attachment
        self.message = message
        self.makesTaskWhenDone = makesTaskWhenDone
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("TRANSCRIPT_TITLE", comment: "Title of a voice message's transcript.")
        view.backgroundColor = .Signal.groupedBackground
        navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)

        textView.font = .dynamicTypeBody
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.backgroundColor = .Signal.secondaryGroupedBackground
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.isHidden = true

        statusLabel.font = .dynamicTypeSubheadline
        statusLabel.textColor = .Signal.secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = IvyLocalizedString("TRANSCRIBING", comment: "Shown while a voice message is turned into text on the device.")

        let status = UIStackView(arrangedSubviews: [spinner, statusLabel])
        status.axis = .vertical
        status.spacing = 12
        status.alignment = .center

        view.addSubview(textView)
        view.addSubview(status)
        textView.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            status.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])

        spinner.startAnimating()
        Task { @MainActor [weak self] in
            await self?.transcribe()
        }
    }

    private func transcribe() async {
        do {
            let text = try await IvyTranscription.transcript(of: attachment)
            spinner.stopAnimating()
            statusLabel.isHidden = true
            textView.text = text
            textView.isHidden = false
            let makeTask = UIBarButtonItem(
                title: IvyLocalizedString("VOICE_NOTE_MAKE_TASK", comment: "Action that turns a voice note into a task, transcribed on the device."),
                primaryAction: UIAction { [weak self] _ in self?.makeTask(from: text) },
            )
            let copy = UIBarButtonItem(
                title: CommonStrings.copyButton,
                primaryAction: UIAction { _ in UIPasteboard.general.string = text },
            )
            navigationItem.rightBarButtonItems = [copy, makeTask]
            if makesTaskWhenDone {
                makeTask(from: text)
            }
        } catch {
            spinner.stopAnimating()
            switch error {
            case .noAccess:
                statusLabel.text = IvyLocalizedString("TRANSCRIPT_NO_ACCESS", comment: "Shown when Ivy may not use speech recognition.")
            case .notOnDevice:
                statusLabel.text = IvyLocalizedString("TRANSCRIPT_NOT_ON_DEVICE", comment: "Shown when the device can't turn speech into text without the internet.")
            case .failed:
                statusLabel.text = IvyLocalizedString("TRANSCRIPT_FAILED", comment: "Shown when a voice message couldn't be turned into text.")
            }
        }
    }

    /// Opens a new task with the transcript in place of this screen.
    private func makeTask(from transcript: String) {
        let task = IvyTask.fromTranscript(transcript, message: message)
        let presenter = presentingViewController
        dismiss(animated: true) {
            presenter?.ivyPresentTaskEditor(task, isNew: true)
        }
    }
}
