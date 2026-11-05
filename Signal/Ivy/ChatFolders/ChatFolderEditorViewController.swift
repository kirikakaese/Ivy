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
            contents.add(notificationsSection())
            contents.add(displaySection())
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

    // MARK: - Display

    /// Whether the folder keeps its chats out of "All chats".
    private func displaySection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("CHAT_FOLDER_DISPLAY", comment: "Header of a chat folder's display options.")
        section.footerTitle = IvyLocalizedString("CHAT_FOLDER_ONLY_HERE_FOOTER", comment: "Explains that a folder's chats then show only in the folder.")
        section.add(.switch(
            withText: IvyLocalizedString("CHAT_FOLDER_ONLY_HERE", comment: "Switch that shows a folder's chats only in that folder, not under All chats."),
            isOn: { [weak self] in self?.extras.showsOnlyHere ?? false },
            actionBlock: { [weak self] uiSwitch in
                self?.extras.showsOnlyHere = uiSwitch.isOn
            },
        ))
        return section
    }

    // MARK: - Notifications

    private func notificationsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("CHAT_FOLDER_NOTIFICATIONS", comment: "Header of the notification hours of a chat folder.")
        section.footerTitle = IvyLocalizedString("CHAT_FOLDER_NOTIFICATIONS_FOOTER", comment: "Explains a chat folder's notification hours.")
        section.add(.disclosureItem(
            withText: IvyLocalizedString("CHAT_FOLDER_NOTIFY", comment: "Item that sets when a chat folder's chats may notify."),
            accessoryText: IvyFocusUI.hoursText(extras.notificationHours),
        ) { [weak self] in
            guard let self else { return }
            let picker = IvyNotificationHoursViewController(hours: extras.notificationHours) { [weak self] hours in
                self?.extras.notificationHours = hours
                self?.updateTableContents()
            }
            navigationController?.pushViewController(picker, animated: true)
        })
        section.add(.disclosureItem(
            withText: IvyLocalizedString("FOLDER_TIMER", comment: "Item in a folder's settings that sets the disappearing messages timer of its chats."),
            accessoryText: IvyFolderTimerUI.title(forSeconds: extras.disappearingSeconds),
        ) { [weak self] in
            self?.chooseTimer()
        })
        return section
    }

    private func chooseTimer() {
        let sheet = ActionSheetController(
            title: IvyLocalizedString("FOLDER_TIMER", comment: "Item in a folder's settings that sets the disappearing messages timer of its chats."),
            message: IvyLocalizedString("FOLDER_TIMER_EXPLANATION", comment: "Explains that a folder's disappearing messages timer is set on its chats and shown to the other people."),
        )
        for seconds in [nil] + IvyFolderTimers.presets.map(Optional.some) {
            sheet.addAction(ActionSheetAction(title: IvyFolderTimerUI.title(forSeconds: seconds)) { [weak self] _ in
                self?.extras.disappearingSeconds = seconds
                self?.updateTableContents()
            })
        }
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
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
        configuration.title = extras.color.map { Self.colorName($0) } ?? IvyLocalizedString("CHAT_FOLDER_COLOR_NONE", comment: "Chat folder has no color.")
        configuration.image = UIImage(systemName: "circle.fill")
        configuration.baseForegroundColor = extras.color.map { ChatFolderBar.uiColor(for: $0) } ?? .Signal.secondaryLabel
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
        let picker = ChatFolderChatPickerViewController(selectedThreadIds: selected, folderName: folder.name) { [weak self] threadIds in
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
        if let seconds = extras.disappearingSeconds {
            IvyFolderTimerUI.apply(seconds: seconds, to: folder)
        }
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

/// Chooses chats for a folder: a search field, suggestions from the names
/// of the chats already chosen and of the folder, and every chat with its
/// picture and a tick.
final class ChatFolderChatPickerViewController: UITableViewController, UISearchResultsUpdating {

    private struct Chat {
        let threadId: String
        let name: String
    }

    private enum Section {
        case suggestions([IvyChatSuggestions.Suggestion])
        case chats(title: String?, [Chat])
    }

    private var chats: [Chat] = []
    private var selectedThreadIds: [String]
    private let folderName: String
    private let onDone: ([String]) -> Void
    private var sections: [Section] = []
    private var query = ""
    private let searchController = UISearchController(searchResultsController: nil)
    private var avatars: [String: UIImage] = [:]

    init(selectedThreadIds: [String], folderName: String = "", onDone: @escaping ([String]) -> Void) {
        self.selectedThreadIds = selectedThreadIds
        self.folderName = folderName
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
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = IvyLocalizedString("CHAT_FOLDER_SEARCH_CHATS", comment: "Placeholder of the search field in the list to choose chats for a folder.")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "chat")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        chats = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let threadStore = DependenciesBridge.shared.threadStore
            return ThreadFinder().visibleInboxThreadUniqueIds(transaction: tx).compactMap { threadId in
                threadStore.fetchThread(uniqueId: threadId, tx: tx).map {
                    Chat(threadId: threadId, name: SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx))
                }
            }
        }
        rebuild()
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        rebuild()
    }

    private func rebuild() {
        let words = IvyChatSuggestions.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty {
            let suggestions = IvyChatSuggestions.suggest(
                chats: chats.map { ($0.threadId, $0.name) },
                selected: Set(selectedThreadIds),
                folderName: folderName,
            )
            sections = (suggestions.isEmpty ? [] : [.suggestions(suggestions)]) + [.chats(
                title: suggestions.isEmpty ? nil : IvyLocalizedString("CHAT_FOLDER_ALL_CHATS", comment: "Header of all chats in the list to choose chats for a folder, below the suggestions."),
                chats,
            )]
        } else {
            let found = chats.filter { chat in
                let name = IvyChatSuggestions.fold(chat.name)
                return words.allSatisfy { name.contains($0) }
            }
            let foundIds = Set(found.map(\.threadId))
            let chosenElsewhere = chats.filter { selectedThreadIds.contains($0.threadId) && !foundIds.contains($0.threadId) }
            sections = [.chats(title: nil, found)]
            if !chosenElsewhere.isEmpty {
                let format = IvyLocalizedString("CHAT_FOLDER_CHOSEN_FORMAT", comment: "Header of the chosen chats while searching the list to choose chats for a folder. Embeds {{ the number of chosen chats }}.")
                sections.append(.chats(title: String(format: format, selectedThreadIds.count), chosenElsewhere))
            }
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .suggestions(let suggestions): suggestions.count
        case .chats(_, let chats): chats.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .suggestions: IvyLocalizedString("CHAT_FOLDER_SUGGESTIONS", comment: "Header of suggested chats in the list to choose chats for a folder.")
        case .chats(let title, _): title
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let threadId: String
        let name: String
        var reason: String?
        switch sections[indexPath.section] {
        case .suggestions(let suggestions):
            let suggestion = suggestions[indexPath.row]
            threadId = suggestion.threadId
            name = chats.first { $0.threadId == threadId }?.name ?? ""
            reason = Self.reasonText(suggestion)
        case .chats(_, let chats):
            threadId = chats[indexPath.row].threadId
            name = chats[indexPath.row].name
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: reason == nil ? "chat" : "suggestion", for: indexPath)
        var configuration = reason == nil ? UIListContentConfiguration.cell() : UIListContentConfiguration.subtitleCell()
        configuration.text = name
        configuration.secondaryText = reason
        configuration.secondaryTextProperties.color = .Signal.secondaryLabel
        configuration.image = avatar(for: threadId)
        configuration.imageProperties.maximumSize = CGSize(width: 32, height: 32)
        configuration.imageProperties.cornerRadius = 16
        cell.contentConfiguration = configuration
        let isSelected = selectedThreadIds.contains(threadId)
        let tick = UIImageView(image: UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle"))
        tick.tintColor = isSelected ? .Signal.accent : .Signal.tertiaryLabel
        tick.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
        cell.accessoryView = tick
        cell.accessibilityTraits = isSelected ? [.button, .selected] : .button
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let threadId: String
        switch sections[indexPath.section] {
        case .suggestions(let suggestions): threadId = suggestions[indexPath.row].threadId
        case .chats(_, let chats): threadId = chats[indexPath.row].threadId
        }
        if let index = selectedThreadIds.firstIndex(of: threadId) {
            selectedThreadIds.remove(at: index)
        } else {
            selectedThreadIds.append(threadId)
        }
        rebuild()
    }

    private func avatar(for threadId: String) -> UIImage? {
        if let cached = avatars[threadId] {
            return cached
        }
        let image = SSKEnvironment.shared.databaseStorageRef.read { tx -> UIImage? in
            guard let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadId, tx: tx) else { return nil }
            return SSKEnvironment.shared.avatarBuilderRef.avatarImage(forThread: thread, diameterPoints: 32, localUserDisplayMode: .asUser, transaction: tx)
        }
        avatars[threadId] = image
        return image
    }

    private static func reasonText(_ suggestion: IvyChatSuggestions.Suggestion) -> String {
        switch suggestion.reason {
        case .chosenChat(let name):
            String(format: IvyLocalizedString("CHAT_FOLDER_SUGGESTION_LIKE_CHAT_FORMAT", comment: "Why a chat is suggested for a folder: it shares a word with one chosen chat. Embeds {{ the word }} and {{ the chosen chat's name }}."), suggestion.word, name)
        case .chosenChats(let count):
            String(format: IvyLocalizedString("CHAT_FOLDER_SUGGESTION_LIKE_CHATS_FORMAT", comment: "Why a chat is suggested for a folder: it shares a word with several chosen chats. Embeds {{ the word }} and {{ the number of chosen chats }}."), suggestion.word, count)
        case .folderName:
            String(format: IvyLocalizedString("CHAT_FOLDER_SUGGESTION_LIKE_FOLDER_FORMAT", comment: "Why a chat is suggested for a folder: it shares a word with the folder's name. Embeds {{ the word }}."), suggestion.word)
        }
    }
}

/// Suggests chats for a folder by the words of their names: chats that
/// share a word with chats already chosen, or with the folder's name.
/// Only names are compared, on the device.
enum IvyChatSuggestions {

    struct Suggestion: Equatable {
        enum Reason: Equatable {
            case chosenChat(String)
            case chosenChats(Int)
            case folderName
        }

        let threadId: String
        /// The shared word, as written in the suggested chat's name.
        let word: String
        let reason: Reason
    }

    static let maxSuggestions = 5

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Words worth comparing: three letters or more, not only digits, not
    /// a common filler word.
    static func words(_ name: String) -> [(folded: String, original: String)] {
        let fillers: Set<String> = ["und", "der", "die", "das", "den", "dem", "fur", "aber", "mit", "von", "the", "and", "for", "with", "chat", "gruppe", "group"]
        return name.split { !$0.isLetter && !$0.isNumber }.compactMap { part in
            let original = String(part)
            let folded = fold(original)
            guard folded.count >= 3, !folded.allSatisfy(\.isNumber), !fillers.contains(folded) else { return nil }
            return (folded, original)
        }
    }

    static func suggest(chats: [(threadId: String, name: String)], selected: Set<String>, folderName: String) -> [Suggestion] {
        let chosen = chats.filter { selected.contains($0.threadId) }
        var chosenByWord: [String: [String]] = [:]
        for chat in chosen {
            for word in Set(words(chat.name).map(\.folded)) {
                chosenByWord[word, default: []].append(chat.name)
            }
        }
        let folderWords = Set(words(folderName).map(\.folded))

        var scored: [(Suggestion, Int)] = []
        for chat in chats where !selected.contains(chat.threadId) {
            var best: (Suggestion, Int)?
            for word in words(chat.name) {
                if let names = chosenByWord[word.folded] {
                    let reason: Suggestion.Reason = names.count == 1 ? .chosenChat(names[0]) : .chosenChats(names.count)
                    let score = names.count + 1
                    if best == nil || score > best!.1 {
                        best = (Suggestion(threadId: chat.threadId, word: word.original, reason: reason), score)
                    }
                } else if folderWords.contains(word.folded), best == nil {
                    best = (Suggestion(threadId: chat.threadId, word: word.original, reason: .folderName), 1)
                }
            }
            if let best {
                scored.append(best)
            }
        }
        return scored
            .enumerated()
            .sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
            .prefix(maxSuggestions)
            .map(\.element.0)
    }
}
