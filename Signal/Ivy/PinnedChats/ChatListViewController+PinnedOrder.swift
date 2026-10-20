//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - Context menu

extension ChatListViewController {

    /// Ivy's entries for a chat's context menu: "Remind Me", "Snooze", "Add
    /// to Folder" and, for pinned chats, "Move Up" and "Move Down".
    func ivyContextMenuElements(threadViewModel: ThreadViewModel) -> [UIMenuElement] {
        var elements = [UIMenuElement]()
        if let chat = IvyChatReference(thread: threadViewModel.threadRecord) {
            elements.append(IvyReminderUI.menu(chat: chat, from: self))
            elements.append(IvySnoozeUI.menu(chat: chat, from: self))
        }
        if let folderMenu = ivyAddToFolderMenu(threadViewModel: threadViewModel) {
            elements.append(folderMenu)
        }
        if let folderPinAction = ivyFolderPinAction(threadViewModel: threadViewModel) {
            elements.append(folderPinAction)
        }
        if let hideAction = ivyHideChatAction(threadViewModel: threadViewModel) {
            elements.append(hideAction)
        }
        if let lockAction = ivyLockChatAction(threadViewModel: threadViewModel) {
            elements.append(lockAction)
        }
        if threadViewModel.isPinned {
            let threadId = threadViewModel.threadUniqueId
            let pinnedIds = renderState.pinnedThreadUniqueIds
            var moveActions = [UIMenuElement]()
            if pinnedIds.first != threadId {
                moveActions.append(UIAction(
                    title: IvyLocalizedString("PINNED_CHAT_MOVE_UP", comment: "Context menu action that moves a pinned chat up."),
                    image: UIImage(systemName: "arrow.up"),
                ) { [weak self] _ in
                    self?.ivyMovePinnedChat(threadId, by: -1)
                })
            }
            if pinnedIds.last != threadId {
                moveActions.append(UIAction(
                    title: IvyLocalizedString("PINNED_CHAT_MOVE_DOWN", comment: "Context menu action that moves a pinned chat down."),
                    image: UIImage(systemName: "arrow.down"),
                ) { [weak self] _ in
                    self?.ivyMovePinnedChat(threadId, by: 1)
                })
            }
            if !moveActions.isEmpty {
                elements.append(UIMenu(options: .displayInline, children: moveActions))
            }
        }
        return elements
    }

    /// Moves a pinned chat past the next visible pinned chat above or below.
    private func ivyMovePinnedChat(_ threadId: String, by offset: Int) {
        var visible = renderState.pinnedThreadUniqueIds
        guard let index = visible.firstIndex(of: threadId) else {
            return
        }
        let newIndex = index + offset
        guard visible.indices.contains(newIndex) else {
            return
        }
        visible.swapAt(index, newIndex)
        ivySetVisiblePinnedOrder(visible)
    }

    fileprivate func ivySetVisiblePinnedOrder(_ visible: [String]) {
        let folderPinned = renderState.viewInfo.ivyFolderPinnedThreadIds
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            // Chats pinned in the folder keep their own order; the others are
            // pinned everywhere.
            if let folder = renderState.viewInfo.ivyChatFolder, !folderPinned.isEmpty {
                let newFolderOrder = visible.filter { folderPinned.contains($0) }
                let threadStore = DependenciesBridge.shared.threadStore
                let references = newFolderOrder.compactMap { threadId in
                    threadStore.fetchThread(uniqueId: threadId, tx: tx).flatMap { IvyChatReference(thread: $0) }
                }
                Self.ivySetFolderPins(references, folderId: folder.id)
            }
            let globalVisible = visible.filter { !folderPinned.contains($0) }
            let all = DependenciesBridge.shared.pinnedThreadManager.pinnedThreads(tx: tx).map(\.uniqueId)
            PinnedChatOrder.setOrder(PinnedChatOrder.order(all: all, visibleInNewOrder: globalVisible), tx: tx)
        }
    }

    // MARK: - Pins in a folder

    private static func ivySetFolderPins(_ pinnedChats: [IvyChatReference], folderId: Data) {
        let store = IvyData.shared?.store
        let old = ChatFolderExtras.fetch(folderId: folderId, store: store)
        var new = old
        new.pinnedChats = pinnedChats
        new.save(folderId: folderId, comparedTo: old, store: store)
    }

    /// "Pin in Folder" or "Unpin from Folder" while a folder is open.
    private func ivyFolderPinAction(threadViewModel: ThreadViewModel) -> UIAction? {
        guard
            let folder = renderState.viewInfo.ivyChatFolder,
            IvyData.shared != nil,
            let chat = IvyChatReference(thread: threadViewModel.threadRecord)
        else {
            return nil
        }
        let pinned = ChatFolderExtras.fetch(folderId: folder.id, store: IvyData.shared?.store).pinnedChats
        if pinned.contains(chat) {
            return UIAction(
                title: IvyLocalizedString("CHAT_FOLDER_UNPIN", comment: "Context menu action that unpins a chat from the open folder."),
                image: UIImage(systemName: "pin.slash"),
            ) { _ in
                Self.ivySetFolderPins(pinned.filter { $0 != chat }, folderId: folder.id)
            }
        }
        return UIAction(
            title: IvyLocalizedString("CHAT_FOLDER_PIN", comment: "Context menu action that pins a chat in the open folder only."),
            image: UIImage(systemName: "pin"),
        ) { [weak self] _ in
            guard pinned.count < ChatFolderExtras.maxPinnedChats else {
                self?.presentToast(text: String.localizedStringWithFormat(
                    IvyLocalizedString("CHAT_FOLDER_PIN_LIMIT_FORMAT", comment: "Shown when a folder already has the most pinned chats. Embeds {{ the maximum number }}."),
                    ChatFolderExtras.maxPinnedChats,
                ))
                return
            }
            Self.ivySetFolderPins(pinned + [chat], folderId: folder.id)
        }
    }
}

// MARK: - Drag and drop

extension CLVTableDataSource: UITableViewDragDelegate {

    /// Lets pinned chats be rearranged by dragging them with touch, mouse or
    /// trackpad.
    func ivyEnablePinnedChatDragging() {
        tableView.dragDelegate = self
        tableView.dragInteractionEnabled = true
    }

    private func isPinnedRow(_ indexPath: IndexPath) -> Bool {
        guard renderState.sections.indices.contains(indexPath.section) else {
            return false
        }
        return renderState.sections[indexPath.section].type == .pinned
    }

    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard
            isPinnedRow(indexPath),
            !tableView.isEditing,
            renderState.pinnedThreadUniqueIds.count > 1,
            let threadId = renderState.threadUniqueId(forIndexPath: indexPath)
        else {
            return []
        }
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = threadId
        return [item]
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return isPinnedRow(indexPath)
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        // Pinned chats stay among the pinned chats.
        guard proposedDestinationIndexPath.section != sourceIndexPath.section else {
            return proposedDestinationIndexPath
        }
        let lastRow = max(renderState.pinnedThreadUniqueIds.count - 1, 0)
        let row = proposedDestinationIndexPath.section < sourceIndexPath.section ? 0 : lastRow
        return IndexPath(row: row, section: sourceIndexPath.section)
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        var pinned = renderState.pinnedThreadUniqueIds
        guard pinned.indices.contains(sourceIndexPath.row), sourceIndexPath.row != destinationIndexPath.row else {
            return
        }
        let threadId = pinned.remove(at: sourceIndexPath.row)
        pinned.insert(threadId, at: min(destinationIndexPath.row, pinned.count))

        // The table shows the new order already. Match it before the database
        // change reloads the chat list.
        renderState = CLVRenderState(
            viewInfo: renderState.viewInfo,
            pinnedThreadUniqueIds: pinned,
            unpinnedThreadUniqueIds: renderState.unpinnedThreadUniqueIds,
        )
        viewController?.ivySetVisiblePinnedOrder(pinned)
    }
}
