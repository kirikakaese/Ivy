//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Chat folders in the chat list: the folder chips or the sidebar's
/// folders, switching folders and the actions for a whole folder.
extension ChatListViewController {

    private var chatFolderManager: ChatFolderManager { .shared }

    func ivyObserveChatFolders() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ivyChatFoldersDidChange),
            name: ChatFolderManager.foldersDidChange,
            object: nil,
        )
        // Folder colors, folder pins and reminders.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ivyChatFoldersDidChange),
            name: IvyReminderManager.remindersDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ivyChatFoldersDidChange),
            name: IvyDataStore.dataDidChange,
            object: nil,
        )
        // Hidden chats hidden, shown or revealed.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ivyChatFoldersDidChange),
            name: IvyHiddenChats.hiddenChatsDidChange,
            object: nil,
        )
        ivyUpdateChatFolderBar()
    }

    @objc
    private func ivyChatFoldersDidChange() {
        ivyUpdateChatFolderBar()
        loadCoordinator.loadIfNecessary()
    }

    /// Shows, hides or refreshes the folders: in the sidebar when there is
    /// one, otherwise as chips above the chats.
    func ivyUpdateChatFolderBar() {
        AssertIsOnMainThread()
        guard viewState.chatListMode == .inbox, isViewLoaded else {
            return
        }

        let (folders, chats) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let folders = chatFolderManager.folders(tx: tx)
            // Counting unread chats is only needed with custom folders.
            let chats = folders.contains { $0.kind == .custom } ? ChatFolderChats.inboxChats(tx: tx) : []
            return (folders, chats)
        }
        if let selectedId = viewState.ivyChatFolderId, !folders.contains(where: { $0.id == selectedId && $0.kind == .custom }) {
            viewState.ivyChatFolderId = nil
            loadCoordinator.loadIfNecessary()
        }

        let counts = ChatFolderChats.unreadCounts(folders: folders, chats: chats)
        let extras = ChatFolderExtras.fetchAll(store: IvyData.shared?.store)
        let items = folders.map { folder in
            ChatFolderBar.Item(folder: folder, unreadCount: counts[folder.id] ?? 0, extras: extras[folder.id] ?? ChatFolderExtras())
        }
        IvySidebarState.shared.update(
            folders: items.filter { $0.folder.kind == .custom },
            allChatsFolder: folders.first { $0.kind == .allChats },
            selectedFolderId: viewState.ivyChatFolderId,
        )

        let showsSidebar = (tabBarController as? HomeTabBarController)?.ivyIsSidebarShown == true
        guard !showsSidebar, folders.contains(where: { $0.kind == .custom }) else {
            ivyRemoveChatFolderBar()
            return
        }

        let bar = ivyChatFolderBar()
        bar.update(items: items, selectedFolderId: viewState.ivyChatFolderId ?? folders.first { $0.kind == .allChats }?.id)
        if tableView.tableHeaderView !== bar {
            bar.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: bar.intrinsicContentSize.height)
            bar.autoresizingMask = [.flexibleWidth]
            tableView.tableHeaderView = bar
        }
    }

    /// Refreshes the unread counts after chats changed.
    func ivyChatsDidChange() {
        ivyUpdateChatFolderBar()
    }

    private var ivyExistingChatFolderBar: ChatFolderBar? {
        return tableView.tableHeaderView as? ChatFolderBar
    }

    private func ivyChatFolderBar() -> ChatFolderBar {
        if let bar = ivyExistingChatFolderBar {
            return bar
        }
        let bar = ChatFolderBar()
        bar.onSelect = { [weak self] folder in
            self?.ivySelectChatFolder(folder)
        }
        bar.menuProvider = { [weak self] folder in
            self?.ivyMenu(for: folder)
        }
        bar.onEditFolders = { [weak self] in
            self?.ivyShowChatFolderSettings()
        }
        return bar
    }

    private func ivyRemoveChatFolderBar() {
        if tableView.tableHeaderView is ChatFolderBar {
            tableView.tableHeaderView = nil
        }
    }

    func ivySelectChatFolder(_ folder: ChatFolder) {
        let id: Data? = folder.kind == .allChats ? nil : folder.id
        guard id != viewState.ivyChatFolderId else {
            return
        }
        viewState.ivyChatFolderId = id
        ivyUpdateChatFolderBar()
        loadCoordinator.loadIfNecessary()
    }

    func ivyShowChatFolderSettings() {
        let settings = ChatFoldersSettingsViewController()
        presentFormSheet(OWSNavigationController(rootViewController: settings), animated: true)
    }

    // MARK: - Folder actions

    func ivyMenu(for folder: ChatFolder) -> UIMenu {
        var actions = [UIMenuElement]()
        actions.append(UIAction(
            title: IvyLocalizedString("CHAT_FOLDER_MARK_READ", comment: "Action that marks every chat in a folder as read."),
            image: .chatCheck,
        ) { [weak self] _ in
            self?.ivyMarkRead(folder)
        })
        actions.append(UIAction(
            title: IvyLocalizedString("CHAT_FOLDER_MUTE", comment: "Action that mutes every chat in a folder."),
            image: .bellSlash,
        ) { [weak self] _ in
            self?.ivyMute(folder)
        })
        actions.append(UIAction(
            title: IvyLocalizedString("CHAT_FOLDER_UNMUTE", comment: "Action that unmutes every chat in a folder."),
            image: .bell,
        ) { [weak self] _ in
            self?.ivyUnmute(folder)
        })
        if folder.kind == .custom {
            actions.append(UIAction(
                title: IvyLocalizedString("CHAT_FOLDER_EDIT", comment: "Action that opens the settings of one chat folder."),
                image: Theme.iconImage(.contextMenuEdit),
            ) { [weak self] _ in
                let editor = ChatFolderEditorViewController(folder: folder)
                self?.presentFormSheet(OWSNavigationController(rootViewController: editor), animated: true)
            })
        }
        actions.append(UIAction(
            title: IvyLocalizedString("CHAT_FOLDERS_EDIT", comment: "Button that opens the chat folder settings."),
            image: Theme.iconImage(.contextMenuSettings),
        ) { [weak self] _ in
            self?.ivyShowChatFolderSettings()
        })
        return UIMenu(title: ChatFolderBar.title(for: folder), children: actions)
    }

    private func ivyThreadViewModels(in folder: ChatFolder, tx: DBReadTransaction) -> [ThreadViewModel] {
        return ChatFolderChats.inboxChats(tx: tx)
            .filter { folder.contains($0) }
            .map { ThreadViewModel(threadUniqueId: $0.threadId, forChatList: true, transaction: tx) }
    }

    private func ivyMarkRead(_ folder: ChatFolder) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            for chat in ChatFolderChats.inboxChats(tx: tx) where chat.isUnread && folder.contains(chat) {
                DependenciesBridge.shared.threadStore.fetchThread(uniqueId: chat.threadId, tx: tx)?
                    .markAllAsRead(updateStorageService: true, transaction: tx)
            }
        }
    }

    private func ivyMute(_ folder: ChatFolder) {
        let threadViewModels = SSKEnvironment.shared.databaseStorageRef.read { tx in
            ivyThreadViewModels(in: folder, tx: tx)
        }
        guard !threadViewModels.isEmpty else {
            return
        }
        let alert = ActionSheetController(title: OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_ACTION_SHEET_TITLE",
            comment: "Title for the mute action sheet",
        ))
        let muteManager = ConversationMuteManager()
        for option in ConversationMuteChoice.Option.all {
            alert.addAction(ActionSheetAction(title: option.title, style: .default) { [weak self] _ in
                switch option {
                case .preset(let preset):
                    muteManager.mute(threadViewModels, choice: .preset(preset))
                case .forever:
                    muteManager.mute(threadViewModels, choice: .forever)
                case .custom:
                    let sheet = MuteUntilSheet { endDate in
                        muteManager.mute(threadViewModels, choice: .custom(endDate: endDate))
                    }
                    self?.present(sheet, animated: true)
                }
            })
        }
        alert.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(alert)
    }

    private func ivyUnmute(_ folder: ChatFolder) {
        let threadViewModels = SSKEnvironment.shared.databaseStorageRef.read { tx in
            ivyThreadViewModels(in: folder, tx: tx).filter(\.isMuted)
        }
        ConversationMuteManager().unmute(threadViewModels)
    }

    // MARK: - Chat actions

    /// "Add to Folder" for a chat's context menu, when there are folders.
    func ivyAddToFolderMenu(threadViewModel: ThreadViewModel) -> UIMenu? {
        let thread = threadViewModel.threadRecord
        let folders = SSKEnvironment.shared.databaseStorageRef.read { tx in
            chatFolderManager.folders(tx: tx).filter { $0.kind == .custom }
        }
        guard !folders.isEmpty else {
            return nil
        }
        let chat = ChatFolderChat(
            threadId: thread.uniqueId,
            isGroup: threadViewModel.isGroupThread,
            isUnread: threadViewModel.hasUnreadMessages,
            isMuted: threadViewModel.isMuted,
        )
        let items = folders.map { folder in
            let isMember = folder.includedThreadIds.contains(chat.threadId)
                || (!folder.excludedThreadIds.contains(chat.threadId)
                    && (chat.isGroup ? folder.includeAllGroupChats : folder.includeAllIndividualChats))
            return UIAction(title: folder.name, state: isMember ? .on : .off) { _ in
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    if isMember {
                        ChatFolderManager.shared.remove(threadId: chat.threadId, isGroup: chat.isGroup, fromFolder: folder.id, tx: tx)
                    } else {
                        ChatFolderManager.shared.add(threadId: chat.threadId, toFolder: folder.id, tx: tx)
                    }
                }
            }
        }
        return UIMenu(
            title: IvyLocalizedString("CHAT_FOLDER_ADD_CHAT", comment: "Context menu of a chat: submenu that adds the chat to a folder or removes it."),
            image: UIImage(systemName: "folder"),
            children: items,
        )
    }
}
