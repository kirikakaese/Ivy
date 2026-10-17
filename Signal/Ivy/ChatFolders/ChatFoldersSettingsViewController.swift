//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The list of chat folders: create, edit, reorder and delete folders, and
/// add suggested folders.
final class ChatFoldersSettingsViewController: OWSTableViewController2 {

    private let manager = ChatFolderManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("CHAT_FOLDERS_TITLE", comment: "Title of the chat folder settings.")
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: ChatFolderManager.foldersDidChange,
            object: nil,
        )
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let folders = SSKEnvironment.shared.databaseStorageRef.read { tx in manager.folders(tx: tx) }
        let customFolders = folders.filter { $0.kind == .custom }

        let contents = OWSTableContents(title: title)

        let foldersSection = OWSTableSection()
        foldersSection.headerTitle = IvyLocalizedString("CHAT_FOLDERS_SECTION", comment: "Header of the list of chat folders.")
        foldersSection.footerTitle = IvyLocalizedString(
            "CHAT_FOLDERS_FOOTER",
            comment: "Footer of the list of chat folders, explaining that folders sync with the user's other devices.",
        )
        foldersSection.add(.item(
            icon: .groupInfoAddMembers,
            name: IvyLocalizedString("CHAT_FOLDER_CREATE", comment: "Item that creates a new chat folder."),
            actionBlock: { [weak self] in
                self?.showEditor(for: nil)
            },
        ))
        for folder in folders {
            let subtitle = folder.kind == .allChats ? nil : Self.summary(of: folder)
            foldersSection.add(.disclosureItem(
                withText: ChatFolderBar.title(for: folder),
                subtitle: subtitle,
                actionBlock: folder.kind == .allChats ? nil : { [weak self] in
                    self?.showEditor(for: folder)
                },
            ))
        }
        if folders.count > 1 {
            foldersSection.add(.disclosureItem(
                withText: IvyLocalizedString("CHAT_FOLDERS_REORDER", comment: "Item that opens the screen to change the order of chat folders."),
                actionBlock: { [weak self] in
                    self?.navigationController?.pushViewController(ChatFolderOrderViewController(), animated: true)
                },
            ))
        }
        contents.add(foldersSection)

        let suggestions = ChatFolderManager.Suggestion.allCases.filter { !$0.isAlreadyAdded(in: customFolders) }
        if !suggestions.isEmpty, customFolders.count < ChatFolderManager.maxCustomFolders {
            let suggestionsSection = OWSTableSection()
            suggestionsSection.headerTitle = IvyLocalizedString("CHAT_FOLDERS_SUGGESTED", comment: "Header of the list of suggested chat folders.")
            for suggestion in suggestions {
                let name = Self.name(of: suggestion)
                suggestionsSection.add(.item(
                    icon: .groupInfoAddMembers,
                    name: name,
                    subtitle: Self.summary(of: suggestion.makeFolder(name: name)),
                    actionBlock: { [weak self] in
                        SSKEnvironment.shared.databaseStorageRef.write { tx in
                            self?.manager.save(suggestion.makeFolder(name: name), tx: tx)
                        }
                    },
                ))
            }
            contents.add(suggestionsSection)
        }

        self.contents = contents
    }

    private func showEditor(for folder: ChatFolder?) {
        if folder == nil {
            let count = SSKEnvironment.shared.databaseStorageRef.read { tx in
                manager.folders(tx: tx).filter { $0.kind == .custom }.count
            }
            guard count < ChatFolderManager.maxCustomFolders else {
                OWSActionSheets.showActionSheet(title: String.localizedStringWithFormat(
                    IvyLocalizedString("CHAT_FOLDERS_LIMIT_FORMAT", comment: "Shown when the user tries to create more chat folders than allowed. Embeds {{ the maximum number of folders }}."),
                    ChatFolderManager.maxCustomFolders,
                ))
                return
            }
        }
        navigationController?.pushViewController(ChatFolderEditorViewController(folder: folder), animated: true)
    }

    static func name(of suggestion: ChatFolderManager.Suggestion) -> String {
        switch suggestion {
        case .unread:
            return IvyLocalizedString("CHAT_FOLDER_SUGGESTED_UNREAD", comment: "Name of the suggested chat folder with unread chats.")
        case .individualChats:
            return IvyLocalizedString("CHAT_FOLDER_SUGGESTED_INDIVIDUAL", comment: "Name of the suggested chat folder with all 1:1 chats.")
        case .groups:
            return IvyLocalizedString("CHAT_FOLDER_SUGGESTED_GROUPS", comment: "Name of the suggested chat folder with all group chats.")
        }
    }

    /// A short description of what a folder shows, such as "All 1:1 chats, 3
    /// chats".
    static func summary(of folder: ChatFolder) -> String {
        var parts = [String]()
        if folder.includeAllIndividualChats {
            parts.append(IvyLocalizedString("CHAT_FOLDER_ALL_INDIVIDUAL", comment: "Chat folder option: the folder contains all 1:1 chats."))
        }
        if folder.includeAllGroupChats {
            parts.append(IvyLocalizedString("CHAT_FOLDER_ALL_GROUPS", comment: "Chat folder option: the folder contains all group chats."))
        }
        let chatCount = folder.includedThreadIds.count + folder.unresolvedIncludedRecipients.count
        if chatCount > 0 {
            parts.append(String.localizedStringWithFormat(
                IvyLocalizedString("CHAT_FOLDER_CHAT_COUNT_FORMAT", comment: "Number of chats added to a folder. Embeds {{ the number of chats }}."),
                chatCount,
            ))
        }
        if folder.showOnlyUnread {
            parts.append(IvyLocalizedString("CHAT_FOLDER_ONLY_UNREAD", comment: "Chat folder option: the folder only shows chats with unread messages."))
        }
        return parts.joined(separator: ", ")
    }
}

/// Changes the order of the chat folders by dragging them.
final class ChatFolderOrderViewController: UITableViewController {

    private var folders: [ChatFolder] = []

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("CHAT_FOLDERS_REORDER", comment: "Item that opens the screen to change the order of chat folders.")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "folder")
        tableView.isEditing = true
        folders = SSKEnvironment.shared.databaseStorageRef.read { tx in ChatFolderManager.shared.folders(tx: tx) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return folders.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "folder", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = ChatFolderBar.title(for: folders[indexPath.row])
        cell.contentConfiguration = configuration
        return cell
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let folder = folders.remove(at: sourceIndexPath.row)
        folders.insert(folder, at: destinationIndexPath.row)
        let ids = folders.map(\.id)
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            ChatFolderManager.shared.reorder(ids, tx: tx)
        }
    }
}
