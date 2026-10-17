//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Creates or edits one chat folder.
final class ChatFolderEditorViewController: OWSTableViewController2 {

    private var folder: ChatFolder
    private let isNew: Bool
    private let nameField = UITextField()
    private let emojiField = UITextField()

    /// Ivy's additions, saved in the Ivy data store.
    private var extras: ChatFolderExtras
    private let originalExtras: ChatFolderExtras

    init(folder: ChatFolder?) {
        self.folder = folder ?? ChatFolder(name: "")
        self.isNew = folder == nil
        self.originalExtras = folder.map { ChatFolderExtras.fetch(folderId: $0.id, store: IvyData.shared?.store) } ?? ChatFolderExtras()
        self.extras = originalExtras
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew
            ? IvyLocalizedString("CHAT_FOLDER_CREATE", comment: "Item that creates a new chat folder.")
            : IvyLocalizedString("CHAT_FOLDER_EDIT", comment: "Action that opens the settings of one chat folder.")

        nameField.text = folder.name
        emojiField.text = extras.emoji
        emojiField.placeholder = IvyLocalizedString("CHAT_FOLDER_EMOJI_PLACEHOLDER", comment: "Placeholder of the emoji field of a chat folder.")
        emojiField.font = .dynamicTypeBody
        emojiField.clearButtonMode = .whileEditing
        emojiField.addAction(UIAction { [weak self] _ in self?.emojiDidChange() }, for: .editingChanged)
        nameField.placeholder = IvyLocalizedString("CHAT_FOLDER_NAME_PLACEHOLDER", comment: "Placeholder of the name field of a chat folder.")
        nameField.font = .dynamicTypeBody
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.addAction(UIAction { [weak self] _ in self?.nameDidChange() }, for: .editingChanged)
        nameField.addAction(UIAction { [weak self] _ in self?.nameField.resignFirstResponder() }, for: .editingDidEndOnExit)

        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        }
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.save() }
        nameDidChange()
        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew, folder.name.isEmpty {
            nameField.becomeFirstResponder()
        }
    }

    private func nameDidChange() {
        folder.name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        navigationItem.rightBarButtonItem?.isEnabled = !folder.name.isEmpty
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: title)

        let nameSection = OWSTableSection()
        nameSection.headerTitle = IvyLocalizedString("CHAT_FOLDER_NAME", comment: "Header of the name field of a chat folder.")
        nameSection.add(.textFieldItem(nameField))
        contents.add(nameSection)

        let includedSection = OWSTableSection()
        includedSection.headerTitle = IvyLocalizedString("CHAT_FOLDER_INCLUDED", comment: "Header of the chats that a folder contains.")
        includedSection.footerTitle = IvyLocalizedString("CHAT_FOLDER_INCLUDED_FOOTER", comment: "Footer of the chats that a folder contains.")
        includedSection.add(.item(
            icon: .groupInfoAddMembers,
            name: IvyLocalizedString("CHAT_FOLDER_ADD_CHATS", comment: "Item that opens a list to choose the chats of a folder."),
            actionBlock: { [weak self] in
                self?.pickChats(excluded: false)
            },
        ))
        includedSection.add(.switch(
            withText: IvyLocalizedString("CHAT_FOLDER_ALL_INDIVIDUAL", comment: "Chat folder option: the folder contains all 1:1 chats."),
            isOn: { [weak self] in self?.folder.includeAllIndividualChats ?? false },
            actionBlock: { [weak self] uiSwitch in
                self?.folder.includeAllIndividualChats = uiSwitch.isOn
                self?.updateTableContents()
            },
        ))
        includedSection.add(.switch(
            withText: IvyLocalizedString("CHAT_FOLDER_ALL_GROUPS", comment: "Chat folder option: the folder contains all group chats."),
            isOn: { [weak self] in self?.folder.includeAllGroupChats ?? false },
            actionBlock: { [weak self] uiSwitch in
                self?.folder.includeAllGroupChats = uiSwitch.isOn
                self?.updateTableContents()
            },
        ))
        for name in chatNames(folder.includedThreadIds) {
            includedSection.add(.label(withText: name, accessoryType: .none))
        }
        contents.add(includedSection)

        if folder.includeAllIndividualChats || folder.includeAllGroupChats {
            let excludedSection = OWSTableSection()
            excludedSection.headerTitle = IvyLocalizedString("CHAT_FOLDER_EXCLUDED", comment: "Header of the chats that a folder leaves out.")
            excludedSection.add(.item(
                icon: .groupInfoAddMembers,
                name: IvyLocalizedString("CHAT_FOLDER_EXCLUDE_CHATS", comment: "Item that opens a list to choose chats that a folder leaves out."),
                actionBlock: { [weak self] in
                    self?.pickChats(excluded: true)
                },
            ))
            for name in chatNames(folder.excludedThreadIds) {
                excludedSection.add(.label(withText: name, accessoryType: .none))
            }
            contents.add(excludedSection)
        }

        if IvyData.shared != nil {
            contents.add(appearanceSection())
        }

        let optionsSection = OWSTableSection()
        optionsSection.headerTitle = IvyLocalizedString("CHAT_FOLDER_OPTIONS", comment: "Header of the options of a chat folder.")
        optionsSection.add(.switch(
            withText: IvyLocalizedString("CHAT_FOLDER_ONLY_UNREAD", comment: "Chat folder option: the folder only shows chats with unread messages."),
            isOn: { [weak self] in self?.folder.showOnlyUnread ?? false },
            actionBlock: { [weak self] uiSwitch in self?.folder.showOnlyUnread = uiSwitch.isOn },
        ))
        optionsSection.add(.switch(
            withText: IvyLocalizedString("CHAT_FOLDER_SHOW_MUTED", comment: "Chat folder option: the folder shows muted chats."),
            isOn: { [weak self] in self?.folder.showMutedChats ?? true },
            actionBlock: { [weak self] uiSwitch in self?.folder.showMutedChats = uiSwitch.isOn },
        ))
        contents.add(optionsSection)

        if !isNew {
            let deleteSection = OWSTableSection()
            deleteSection.add(.actionItem(
                withText: IvyLocalizedString("CHAT_FOLDER_DELETE", comment: "Item that deletes a chat folder."),
                textColor: .Signal.red,
                actionBlock: { [weak self] in
                    self?.confirmDelete()
                },
            ))
            contents.add(deleteSection)
        }

        self.contents = contents
    }

    // MARK: - Emoji and color

    private func emojiDidChange() {
        // Keep only the last character typed, which is one emoji.
        let text = emojiField.text ?? ""
        let emoji = text.last.map(String.init)
        if emojiField.text != (emoji ?? "") {
            emojiField.text = emoji ?? ""
        }
        extras.emoji = emoji
    }

    private func appearanceSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("CHAT_FOLDER_APPEARANCE", comment: "Header of the emoji and color of a chat folder.")
        section.footerTitle = IvyLocalizedString("CHAT_FOLDER_APPEARANCE_FOOTER", comment: "Footer explaining that a folder's emoji, color and pins only appear in Ivy.")
        section.add(.textFieldItem(emojiField))

        let colorButton = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = extras.color.map(Self.colorName) ?? IvyLocalizedString("CHAT_FOLDER_COLOR_NONE", comment: "Chat folder has no color.")
        configuration.image = UIImage(systemName: "circle.fill")
        configuration.baseForegroundColor = extras.color.map(ChatFolderBar.uiColor(for:)) ?? .Signal.secondaryLabel
        configuration.imagePadding = 6
        colorButton.configuration = configuration
        colorButton.showsMenuAsPrimaryAction = true
        let noColor = UIAction(title: IvyLocalizedString("CHAT_FOLDER_COLOR_NONE", comment: "Chat folder has no color.")) { [weak self] _ in
            self?.extras.color = nil
            self?.updateTableContents()
        }
        colorButton.menu = UIMenu(children: [noColor] + ChatFolderColor.allCases.map { color in
            UIAction(
                title: Self.colorName(color),
                image: UIImage(systemName: "circle.fill")?.withTintColor(ChatFolderBar.uiColor(for: color), renderingMode: .alwaysOriginal),
                state: extras.color == color ? .on : .off,
            ) { [weak self] _ in
                self?.extras.color = color
                self?.updateTableContents()
            }
        })
        section.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            var content = cell.defaultContentConfiguration()
            content.text = IvyLocalizedString("CHAT_FOLDER_COLOR", comment: "Label of the color of a chat folder.")
            cell.contentConfiguration = content
            cell.accessoryView = colorButton
            colorButton.sizeToFit()
            return cell
        }))
        return section
    }

    static func colorName(_ color: ChatFolderColor) -> String {
        switch color {
        case .green: return IvyLocalizedString("COLOR_GREEN", comment: "Color name.")
        case .teal: return IvyLocalizedString("COLOR_TEAL", comment: "Color name.")
        case .blue: return IvyLocalizedString("COLOR_BLUE", comment: "Color name.")
        case .indigo: return IvyLocalizedString("COLOR_INDIGO", comment: "Color name.")
        case .purple: return IvyLocalizedString("COLOR_PURPLE", comment: "Color name.")
        case .pink: return IvyLocalizedString("COLOR_PINK", comment: "Color name.")
        case .red: return IvyLocalizedString("COLOR_RED", comment: "Color name.")
        case .orange: return IvyLocalizedString("COLOR_ORANGE", comment: "Color name.")
        case .yellow: return IvyLocalizedString("COLOR_YELLOW", comment: "Color name.")
        case .gray: return IvyLocalizedString("COLOR_GRAY", comment: "Color name.")
        }
    }

    private func chatNames(_ threadIds: [String]) -> [String] {
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            threadIds.compactMap { threadId in
                DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadId, tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                }
            }
        }
    }

    private func pickChats(excluded: Bool) {
        let selected = excluded ? folder.excludedThreadIds : folder.includedThreadIds
        let picker = ChatFolderChatPickerViewController(selectedThreadIds: selected) { [weak self] threadIds in
            guard let self else { return }
            if excluded {
                folder.excludedThreadIds = threadIds
                folder.includedThreadIds.removeAll { threadIds.contains($0) }
            } else {
                folder.includedThreadIds = threadIds
                folder.excludedThreadIds.removeAll { threadIds.contains($0) }
            }
            updateTableContents()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func save() {
        nameDidChange()
        guard !folder.name.isEmpty else {
            return
        }
        let folder = self.folder
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            ChatFolderManager.shared.save(folder, tx: tx)
        }
        extras.save(folderId: folder.id, comparedTo: originalExtras, store: IvyData.shared?.store)
        close()
    }

    private func confirmDelete() {
        let sheet = ActionSheetController(
            title: IvyLocalizedString("CHAT_FOLDER_DELETE_CONFIRM_TITLE", comment: "Title of the confirmation before deleting a chat folder."),
            message: IvyLocalizedString("CHAT_FOLDER_DELETE_CONFIRM_MESSAGE", comment: "Message of the confirmation before deleting a chat folder."),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("CHAT_FOLDER_DELETE", comment: "Item that deletes a chat folder."),
            style: .destructive,
        ) { [weak self] _ in
            guard let self else { return }
            let id = folder.id
            SSKEnvironment.shared.databaseStorageRef.write { tx in
                ChatFolderManager.shared.delete(id: id, tx: tx)
            }
            ChatFolderExtras.delete(folderId: id, store: IvyData.shared?.store)
            close()
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    private func close() {
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

/// Chooses chats for a folder.
final class ChatFolderChatPickerViewController: UITableViewController {

    private struct Chat {
        let threadId: String
        let name: String
    }

    private var chats: [Chat] = []
    private var selectedThreadIds: [String]
    private let onDone: ([String]) -> Void

    init(selectedThreadIds: [String], onDone: @escaping ([String]) -> Void) {
        self.selectedThreadIds = selectedThreadIds
        self.onDone = onDone
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("CHAT_FOLDER_CHOOSE_CHATS", comment: "Title of the list to choose chats for a folder.")
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            guard let self else { return }
            onDone(selectedThreadIds)
            navigationController?.popViewController(animated: true)
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chat")
        chats = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let threadStore = DependenciesBridge.shared.threadStore
            return ThreadFinder().visibleInboxThreadUniqueIds(transaction: tx).compactMap { threadId in
                threadStore.fetchThread(uniqueId: threadId, tx: tx).map {
                    Chat(threadId: threadId, name: SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx))
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chats.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let chat = chats[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = chat.name
        cell.contentConfiguration = configuration
        cell.accessoryType = selectedThreadIds.contains(chat.threadId) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let threadId = chats[indexPath.row].threadId
        if let index = selectedThreadIds.firstIndex(of: threadId) {
            selectedThreadIds.remove(at: index)
        } else {
            selectedThreadIds.append(threadId)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
