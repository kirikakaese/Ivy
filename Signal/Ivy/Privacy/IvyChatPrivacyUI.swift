//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import LocalAuthentication
import SignalServiceKit
import SignalUI

// MARK: - Locked chats

enum IvyChatLock {

    /// Asks for Ivy's passcode when one is set, otherwise for Face ID,
    /// Touch ID or the device passcode.
    @MainActor
    static func authenticate(from viewController: UIViewController, reason: String, completion: @escaping (Bool) -> Void) {
        if IvyPasscodeLock.isSet {
            let entry = IvyPasscodeEntryViewController { outcome in
                if case .success = outcome {
                    completion(true)
                } else {
                    completion(false)
                }
            }
            entry.modalPresentationStyle = .fullScreen
            viewController.present(entry, animated: true)
            return
        }
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            if let error {
                Logger.info("Chat stays locked: \(error)")
            }
            DispatchQueue.main.async { completion(success) }
        }
    }

    static var reason: String {
        IvyLocalizedString("LOCKED_CHAT_REASON", comment: "Shown by Face ID, Touch ID or the passcode prompt when opening a locked chat.")
    }
}

/// Covers a locked chat until the user proves it's them.
private final class IvyChatLockCover: UIView {

    let openButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .Signal.background

        let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
        icon.tintColor = .Signal.accent
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
        let label = UILabel()
        label.text = IvyLocalizedString("LOCKED_CHAT_TITLE", comment: "Shown over a locked chat until it is opened.")
        label.font = .dynamicTypeTitle3.semibold()
        label.textColor = .Signal.label
        label.textAlignment = .center
        var configuration = UIButton.Configuration.filled()
        configuration.title = IvyLocalizedString("LOCKED_CHAT_OPEN", comment: "Button that opens a locked chat with Face ID, Touch ID or a passcode.")
        configuration.baseBackgroundColor = .Signal.accent
        configuration.cornerStyle = .large
        openButton.configuration = configuration

        let stack = UIStackView(arrangedSubviews: [icon, label, openButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        addSubview(stack)
        stack.autoCenterInSuperview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ConversationViewController {

    private static var ivyCoverKey: UInt8 = 0
    private static var ivyObserverKey: UInt8 = 0

    private var ivyLockCover: IvyChatLockCover? {
        get { objc_getAssociatedObject(self, &Self.ivyCoverKey) as? IvyChatLockCover }
        set { objc_setAssociatedObject(self, &Self.ivyCoverKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Covers a locked chat and asks to open it. Called whenever the chat
    /// appears or Ivy comes back to the screen.
    func ivyGuardLockedChat() {
        if objc_getAssociatedObject(self, &Self.ivyObserverKey) == nil {
            let observer = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.ivyGuardLockedChat() }
            }
            objc_setAssociatedObject(self, &Self.ivyObserverKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        guard let chat = IvyChatReference(thread: thread), !IvyLockedChats.shared.isOpen(chat) else {
            ivyLockCover?.removeFromSuperview()
            ivyLockCover = nil
            return
        }
        if ivyLockCover == nil {
            let cover = IvyChatLockCover()
            cover.openButton.addAction(UIAction { [weak self] _ in self?.ivyOpenLockedChat() }, for: .primaryActionTriggered)
            view.addSubview(cover)
            cover.autoPinEdgesToSuperviewEdges()
            ivyLockCover = cover
        }
        view.bringSubviewToFront(ivyLockCover!)
        DispatchQueue.main.async { [weak self] in
            guard let self, view.window != nil, UIApplication.shared.applicationState == .active else { return }
            ivyOpenLockedChat()
        }
    }

    private func ivyOpenLockedChat() {
        guard let chat = IvyChatReference(thread: thread), presentedViewController == nil else {
            return
        }
        IvyChatLock.authenticate(from: self, reason: IvyChatLock.reason) { [weak self] success in
            guard success else { return }
            IvyLockedChats.shared.markOpened(chat)
            self?.ivyGuardLockedChat()
        }
    }
}

extension ChatListViewController {

    /// "Lock Chat" or "Unlock Chat" for a chat's context menu.
    func ivyLockChatAction(threadViewModel: ThreadViewModel) -> UIAction? {
        guard let chat = IvyChatReference(thread: threadViewModel.threadRecord) else {
            return nil
        }
        if IvyLockedChats.shared.isLocked(chat) {
            return UIAction(
                title: IvyLocalizedString("LOCKED_CHAT_UNLOCK", comment: "Context menu action that stops a chat from asking for Face ID, Touch ID or a passcode."),
                image: UIImage(systemName: "lock.open"),
            ) { [weak self] _ in
                guard let self else { return }
                IvyChatLock.authenticate(from: self, reason: IvyChatLock.reason) { success in
                    if success {
                        IvyLockedChats.shared.setLocked(false, chat: chat)
                    }
                }
            }
        }
        return UIAction(
            title: IvyLocalizedString("LOCKED_CHAT_LOCK", comment: "Context menu action that makes a chat ask for Face ID, Touch ID or a passcode to open."),
            image: UIImage(systemName: "lock"),
        ) { [weak self] _ in
            IvyLockedChats.shared.setLocked(true, chat: chat)
            self?.presentToast(text: IvyLocalizedString("LOCKED_CHAT_LOCKED_TOAST", comment: "Shown after locking a chat."))
        }
    }
}

// MARK: - Link previews per chat

extension ConversationInputToolbar {

    /// Whether this chat has link previews turned off.
    var ivyLinkPreviewsOff: Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let conversation = current as? ConversationViewController {
                return IvyChatReference(thread: conversation.thread).map { IvyLinkPreviews.areOff(for: $0) } ?? false
            }
            responder = current.next
        }
        return false
    }
}

extension ConversationSettingsViewController {

    /// "Link Previews" for this chat.
    func ivyAddLinkPreviewItem(to section: OWSTableSection) {
        guard let chat = IvyChatReference(thread: thread), IvyData.shared != nil else {
            return
        }
        section.add(.switch(
            withText: IvyLocalizedString("CHAT_LINK_PREVIEWS", comment: "Switch in a chat's settings that turns link previews on or off for this chat."),
            isOn: { !IvyLinkPreviews.areOff(for: chat) },
            actionBlock: { uiSwitch in
                IvyLinkPreviews.setOff(!uiSwitch.isOn, for: chat)
            },
        ))
    }
}

// MARK: - Disappearing messages per folder

enum IvyFolderTimerUI {

    static func title(forSeconds seconds: UInt32?) -> String {
        guard let seconds else {
            return IvyLocalizedString("FOLDER_TIMER_EACH_CHAT", comment: "A folder leaves the disappearing messages timer to each chat.")
        }
        if seconds == 0 {
            return CommonStrings.switchOff
        }
        return String.formatDurationLossless(durationSeconds: seconds)
    }

    /// Sets the folder's timer on its chats that have another one. Changes
    /// show in the chats like any timer change.
    @MainActor
    static func apply(seconds: UInt32, to folder: ChatFolder, onlyThreadId: String? = nil) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let changes: [(TSThread, VersionedDisappearingMessageToken)] = databaseStorage.read { tx in
            ChatFolderChats.inboxChats(tx: tx).compactMap { chat in
                guard
                    onlyThreadId == nil || chat.threadId == onlyThreadId,
                    folder.isMember(threadId: chat.threadId, isGroup: chat.isGroup),
                    let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: chat.threadId, tx: tx),
                    !thread.isNoteToSelf
                else {
                    return nil
                }
                let current = DependenciesBridge.shared.disappearingMessagesConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)
                return IvyFolderTimers.token(forSeconds: seconds, current: current).map { (thread, $0) }
            }
        }
        for (thread, token) in changes {
            if let contactThread = thread as? TSContactThread {
                databaseStorage.write { tx in
                    GroupManager.localUpdateDisappearingMessageToken(token, inContactThread: contactThread, tx: tx)
                }
            } else if let groupThread = thread as? TSGroupThread, let groupModel = groupThread.groupModel as? TSGroupModelV2 {
                Task {
                    do {
                        _ = try await GroupManager.updateGroupV2(
                            secretParams: try groupModel.secretParams(),
                            description: "Folder disappearing messages",
                        ) { changeSet in
                            changeSet.setNewDisappearingMessageToken(token.unversioned)
                        }
                    } catch {
                        Logger.warn("Couldn't set a group's timer from its folder: \(error)")
                    }
                }
            }
        }
    }
}
