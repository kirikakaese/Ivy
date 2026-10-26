//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

/// Searching everything and the library of links, photos and files.
enum IvyFind {

    static var searchTitle: String {
        IvyLocalizedString("SEARCH_EVERYTHING", comment: "Title of the search across chats, tasks, events and chat notes.")
    }

    static var libraryTitle: String {
        IvyLocalizedString("LIBRARY_TITLE", comment: "Title of the list of every link, photo and file from all chats.")
    }

    static func presentSearch(from viewController: UIViewController) {
        viewController.presentFormSheet(OWSNavigationController(rootViewController: IvySearchViewController()), animated: true)
    }

    static func presentLibrary(from viewController: UIViewController) {
        viewController.presentFormSheet(OWSNavigationController(rootViewController: IvyLibraryViewController()), animated: true)
    }

    /// Closes the search or library, then shows the message in its chat.
    static func showMessage(threadUniqueId: String, messageUniqueId: String, from viewController: UIViewController) {
        viewController.dismiss(animated: true) {
            SignalApp.shared.presentConversationForThread(
                threadUniqueId: threadUniqueId,
                focusMessageId: messageUniqueId,
                animated: true,
            )
        }
    }

    static func chatName(threadUniqueId: String, tx: DBReadTransaction) -> String {
        guard let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: threadUniqueId, tx: tx) else {
            return ""
        }
        return SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
    }

    static func dateText(_ timestamp: UInt64) -> String {
        DateFormatter.localizedString(from: Date(millisecondsSince1970: timestamp), dateStyle: .medium, timeStyle: .short)
    }
}

// MARK: - Filters

/// The chat, person, date and type filters: a filter button that opens
/// one menu, and a row of the filters that are on, each with a way to
/// turn it off. The row only shows while a filter is on.
final class IvyFilterBar: UIView {

    enum DateRange: CaseIterable {
        case any
        case today
        case week
        case month
        case year

        func since(now: Date = Date()) -> Date? {
            let calendar = Calendar.current
            switch self {
            case .any: return nil
            case .today: return calendar.startOfDay(for: now)
            case .week: return calendar.date(byAdding: .day, value: -7, to: now)
            case .month: return calendar.date(byAdding: .month, value: -1, to: now)
            case .year: return calendar.date(byAdding: .year, value: -1, to: now)
            }
        }

        var title: String {
            switch self {
            case .any: return IvyLocalizedString("FILTER_DATE_ANY", comment: "Search filter: messages from any date.")
            case .today: return IvyLocalizedString("FILTER_DATE_TODAY", comment: "Search filter: messages from today.")
            case .week: return IvyLocalizedString("FILTER_DATE_WEEK", comment: "Search filter: messages from the last 7 days.")
            case .month: return IvyLocalizedString("FILTER_DATE_MONTH", comment: "Search filter: messages from the last 30 days.")
            case .year: return IvyLocalizedString("FILTER_DATE_YEAR", comment: "Search filter: messages from the last year.")
            }
        }
    }

    private(set) var filter = IvySearchFilter()
    private var dateRange = DateRange.any
    private var chatName: String?
    private var personName: String?
    private let showsContent: Bool
    private let onChange: (IvySearchFilter) -> Void
    private weak var presenter: UIViewController?

    /// The filter button, for the navigation bar.
    let barButtonItem = UIBarButtonItem()
    /// The same button, for inside a search field.
    let fieldButton = UIButton(type: .system)
    private let chipStack = UIStackView()

    /// Whether any filter is on.
    var isActive: Bool {
        filter.threadUniqueId != nil || filter.author != nil || filter.since != nil || filter.content != .any
    }

    init(showsContent: Bool, presenter: UIViewController, onChange: @escaping (IvySearchFilter) -> Void) {
        self.showsContent = showsContent
        self.presenter = presenter
        self.onChange = onChange
        super.init(frame: .zero)

        backgroundColor = .Signal.groupedBackground
        chipStack.axis = .horizontal
        chipStack.spacing = 8
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.addSubview(chipStack)
        addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()
        chipStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        chipStack.autoMatch(.height, to: .height, of: scrollView, withOffset: -16)
        let separator = UIView()
        separator.backgroundColor = .Signal.opaqueSeparator
        addSubview(separator)
        separator.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        separator.autoSetDimension(.height, toSize: 1 / UIScreen.main.scale)
        autoSetDimension(.height, toSize: 52)
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var chatLabel: String {
        IvyLocalizedString("FILTER_LABEL_CHAT", comment: "Name of the search filter that limits results to one chat.")
    }

    private static var fromLabel: String {
        IvyLocalizedString("FILTER_LABEL_FROM", comment: "Name of the search filter that limits results to messages from one person.")
    }

    private static var dateLabel: String {
        IvyLocalizedString("FILTER_LABEL_DATE", comment: "Name of the search filter that limits results to a time span.")
    }

    private static var typeLabel: String {
        IvyLocalizedString("FILTER_LABEL_TYPE", comment: "Name of the search filter for links, photos or files.")
    }

    private func update() {
        barButtonItem.image = UIImage(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        barButtonItem.accessibilityLabel = IvyLocalizedString("FILTER_BUTTON", comment: "Button that opens the search filters.")
        barButtonItem.menu = filterMenu()
        fieldButton.setImage(barButtonItem.image, for: .normal)
        fieldButton.tintColor = .Signal.accent
        fieldButton.accessibilityLabel = barButtonItem.accessibilityLabel
        fieldButton.menu = barButtonItem.menu
        fieldButton.showsMenuAsPrimaryAction = true

        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let chatName, filter.threadUniqueId != nil {
            addChip(label: Self.chatLabel, value: chatName) { $0.filter.threadUniqueId = nil; $0.chatName = nil }
        }
        if let personName, filter.author != nil {
            addChip(label: Self.fromLabel, value: personName) { $0.filter.author = nil; $0.personName = nil }
        }
        if dateRange != .any {
            addChip(label: Self.dateLabel, value: dateRange.title) { $0.dateRange = .any; $0.filter.since = nil }
        }
        if filter.content != .any {
            addChip(label: Self.typeLabel, value: Self.title(for: filter.content)) { $0.filter.content = .any }
        }
        var clearConfiguration = UIButton.Configuration.plain()
        clearConfiguration.title = IvyLocalizedString("FILTER_CLEAR", comment: "Button that turns off all search filters.")
        clearConfiguration.baseForegroundColor = .Signal.accent
        clearConfiguration.buttonSize = .small
        let clearButton = UIButton(configuration: clearConfiguration, primaryAction: UIAction { [weak self] _ in self?.clear() })
        chipStack.addArrangedSubview(clearButton)
        isHidden = !isActive
    }

    /// A filter that is on: its value, and a cross that turns it off.
    private func addChip(label: String, value: String, remove: @escaping (IvyFilterBar) -> Void) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = value
        configuration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .Signal.accent
        configuration.baseForegroundColor = .white
        configuration.buttonSize = .medium
        configuration.titleLineBreakMode = .byTruncatingTail
        let chip = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            remove(self)
            self.changed()
        })
        chip.accessibilityLabel = label + ": " + value
        chip.accessibilityHint = IvyLocalizedString("FILTER_REMOVE_HINT", comment: "Accessibility hint on an active search filter: tapping turns it off.")
        chip.setContentHuggingPriority(.required, for: .horizontal)
        chipStack.addArrangedSubview(chip)
    }

    /// One menu with every filter, each in its own section.
    private func filterMenu() -> UIMenu {
        var sections: [UIMenuElement] = []

        var chatItems: [UIMenuElement] = [
            UIAction(title: IvyLocalizedString("FILTER_CHAT_ANY", comment: "Search filter: messages from any chat."), state: filter.threadUniqueId == nil ? .on : .off) { [weak self] _ in
                self?.filter.threadUniqueId = nil
                self?.chatName = nil
                self?.changed()
            },
        ]
        if let chatName, filter.threadUniqueId != nil {
            chatItems.append(UIAction(title: chatName, state: .on) { _ in })
        }
        chatItems.append(UIAction(title: IvyLocalizedString("FILTER_CHOOSE", comment: "Search filter action that chooses a chat or person."), image: UIImage(systemName: "bubble.left.and.bubble.right")) { [weak self] _ in
            self?.chooseChat()
        })
        sections.append(UIMenu(title: Self.chatLabel, options: .displayInline, children: chatItems))

        var personItems: [UIMenuElement] = [
            UIAction(title: IvyLocalizedString("FILTER_PERSON_ANY", comment: "Search filter: messages from anyone."), state: filter.author == nil ? .on : .off) { [weak self] _ in
                self?.filter.author = nil
                self?.personName = nil
                self?.changed()
            },
        ]
        if let personName, filter.author != nil {
            personItems.append(UIAction(title: personName, state: .on) { _ in })
        }
        personItems.append(UIAction(title: IvyLocalizedString("FILTER_CHOOSE", comment: "Search filter action that chooses a chat or person."), image: UIImage(systemName: "person")) { [weak self] _ in
            self?.choosePerson()
        })
        sections.append(UIMenu(title: Self.fromLabel, options: .displayInline, children: personItems))

        sections.append(UIMenu(title: Self.dateLabel, subtitle: dateRange.title, image: UIImage(systemName: "calendar"), children: DateRange.allCases.map { range in
            UIAction(title: range.title, state: range == dateRange ? .on : .off) { [weak self] _ in
                self?.dateRange = range
                self?.filter.since = range.since()
                self?.changed()
            }
        }))

        if showsContent {
            sections.append(UIMenu(title: Self.typeLabel, subtitle: Self.title(for: filter.content), image: UIImage(systemName: "paperclip"), children: IvySearchFilter.Content.allCases.map { content in
                UIAction(title: Self.title(for: content), state: content == filter.content ? .on : .off) { [weak self] _ in
                    self?.filter.content = content
                    self?.changed()
                }
            }))
        }

        if isActive {
            sections.append(UIMenu(options: .displayInline, children: [
                UIAction(title: IvyLocalizedString("FILTER_CLEAR_ALL", comment: "Menu action that turns off all search filters."), image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                    self?.clear()
                },
            ]))
        }
        return UIMenu(title: IvyLocalizedString("FILTER_BUTTON", comment: "Button that opens the search filters."), children: sections)
    }

    static func title(for content: IvySearchFilter.Content) -> String {
        switch content {
        case .any: return IvyLocalizedString("FILTER_TYPE_ANY", comment: "Search filter: any kind of message.")
        case .link: return IvyLocalizedString("FILTER_TYPE_LINK", comment: "Search filter: messages with a link.")
        case .photo: return IvyLocalizedString("FILTER_TYPE_PHOTO", comment: "Search filter: messages with a photo or video.")
        case .file: return IvyLocalizedString("FILTER_TYPE_FILE", comment: "Search filter: messages with a file.")
        }
    }

    private func changed() {
        update()
        onChange(filter)
    }

    func setContent(_ content: IvySearchFilter.Content) {
        filter.content = content
        changed()
    }

    func clear() {
        filter = IvySearchFilter()
        dateRange = .any
        chatName = nil
        personName = nil
        changed()
    }

    func chooseChat() {
        let chooser = IvyChatChooserViewController(preferredChat: nil) { [weak self] thread in
            guard let self else { return }
            filter.threadUniqueId = thread.uniqueId
            chatName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
            }
            changed()
        }
        chooser.title = IvyLocalizedString("FILTER_CHOOSE_CHAT", comment: "Title of the list that chooses the chat to search in.")
        presenter?.presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
    }

    func choosePerson() {
        let chooser = IvyChatChooserViewController(preferredChat: nil) { [weak self] thread in
            guard let self else { return }
            guard let contactThread = thread as? TSContactThread, let aci = contactThread.contactAddress.aci else {
                presenter?.presentToast(text: IvyLocalizedString("FILTER_PERSON_NEEDS_CONTACT", comment: "Shown when a group is chosen as the person to search for."))
                return
            }
            filter.author = aci
            personName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
            }
            changed()
        }
        chooser.title = IvyLocalizedString("FILTER_CHOOSE_PERSON", comment: "Title of the list that chooses the person whose messages to search.")
        presenter?.presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
    }
}

// MARK: - Search

/// One search across chats, tasks, events and chat notes.
final class IvySearchViewController: UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {

    private enum Section {
        case messages([IvySearchResult])
        case tasks([IvySearchResult])
        case events([IvySearchResult])
        case notes([IvySearchResult])

        var results: [IvySearchResult] {
            switch self {
            case .messages(let results), .tasks(let results), .events(let results), .notes(let results):
                return results
            }
        }

        var title: String {
            switch self {
            case .messages: return IvyLocalizedString("SEARCH_SECTION_MESSAGES", comment: "Header of the messages found by a search.")
            case .tasks: return IvyTaskUI.tasksTitle
            case .events: return IvyLocalizedString("SEARCH_SECTION_EVENTS", comment: "Header of the calendar events found by a search.")
            case .notes: return IvyChatNoteViewController.title
            }
        }
    }

    /// Shown before anything is typed: shortcuts to the filters.
    private enum Suggestion: CaseIterable {
        case links
        case photos
        case files
        case inChat
        case from
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private var showsSuggestions = true
    private var filterBar: IvyFilterBar?
    private var sections = [Section]()
    private var chatNames = [String: String]()
    private var searchGeneration = 0

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyFind.searchTitle
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = IvyLocalizedString("SEARCH_EVERYTHING_PLACEHOLDER", comment: "Placeholder of the search across chats, tasks, events and chat notes.")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "result")
        tableView.keyboardDismissMode = .onDrag

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")

        // The filters stay in view above the results.
        let bar = IvyFilterBar(showsContent: true, presenter: self) { [weak self] _ in self?.runSearch() }
        filterBar = bar
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.dismiss(animated: true) }
        // The filter button sits right next to the search field.
        bar.fieldButton.setContentHuggingPriority(.required, for: .horizontal)
        bar.fieldButton.autoSetDimensions(to: CGSize(width: 36, height: 36))
        let searchRow = UIStackView(arrangedSubviews: [searchBar, bar.fieldButton])
        searchRow.alignment = .center
        searchRow.spacing = 4
        searchRow.isLayoutMarginsRelativeArrangement = true
        searchRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12)
        let stack = UIStackView(arrangedSubviews: [searchRow, bar, tableView])
        stack.axis = .vertical
        view.backgroundColor = .Signal.groupedBackground
        view.addSubview(stack)
        stack.autoPinEdge(toSuperviewSafeArea: .top)
        stack.autoPinEdge(toSuperviewEdge: .leading)
        stack.autoPinEdge(toSuperviewEdge: .trailing)
        stack.autoPinEdge(toSuperviewEdge: .bottom)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        runSearch()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    /// Searches a moment after typing stops, off the main thread.
    private func runSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        let text = searchBar.text ?? ""
        let filter = filterBar?.filter ?? IvySearchFilter()
        let tasks = IvyTaskManager.shared.allTasks()
        let events = IvyEventManager.shared.allEvents()
        let notes = IvyChatNoteStore.all(store: IvyData.shared?.store)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard self != nil else { return }
            let (results, names) = SSKEnvironment.shared.databaseStorageRef.read { tx in
                let results = IvySearch.search(text, filter: filter, tasks: tasks, events: events, chatNotes: notes, tx: tx)
                var names = [String: String]()
                for result in results {
                    switch result {
                    case .message(let threadId, _, _, _):
                        if names[threadId] == nil {
                            names[threadId] = IvyFind.chatName(threadUniqueId: threadId, tx: tx)
                        }
                    case .chatNote(let chat, _):
                        if let thread = chat.thread(tx: tx) {
                            names[chat.rawValue] = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                        }
                    case .task, .event:
                        break
                    }
                }
                return (results, names)
            }
            DispatchQueue.main.async {
                guard let self, generation == self.searchGeneration else { return }
                self.show(results, names: names)
            }
        }
    }

    private func show(_ results: [IvySearchResult], names: [String: String]) {
        var messages = [IvySearchResult]()
        var tasks = [IvySearchResult]()
        var events = [IvySearchResult]()
        var notes = [IvySearchResult]()
        for result in results {
            switch result {
            case .message: messages.append(result)
            case .task: tasks.append(result)
            case .event: events.append(result)
            case .chatNote: notes.append(result)
            }
        }
        sections = [Section.messages(messages), .tasks(tasks), .events(events), .notes(notes)].filter { !$0.results.isEmpty }
        chatNames = names
        let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        showsSuggestions = query.isEmpty && results.isEmpty && filterBar?.isActive != true
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        showsSuggestions ? 1 : sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        showsSuggestions ? Suggestion.allCases.count : sections[section].results.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        showsSuggestions
            ? IvyLocalizedString("SEARCH_SUGGESTIONS", comment: "Header of the filter shortcuts shown before anything is searched.")
            : sections[section].title
    }

    private func suggestionCell(_ suggestion: Suggestion, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "suggestion", for: indexPath)
        var content = UIListContentConfiguration.cell()
        content.imageProperties.tintColor = .Signal.accent
        switch suggestion {
        case .links:
            content.text = IvyFilterBar.title(for: .link)
            content.image = UIImage(systemName: "link")
        case .photos:
            content.text = IvyFilterBar.title(for: .photo)
            content.image = UIImage(systemName: "photo")
        case .files:
            content.text = IvyFilterBar.title(for: .file)
            content.image = UIImage(systemName: "doc")
        case .inChat:
            content.text = IvyLocalizedString("FILTER_CHOOSE_CHAT", comment: "Title of the list that chooses the chat to search in.") + "…"
            content.image = UIImage(systemName: "bubble.left.and.bubble.right")
        case .from:
            content.text = IvyLocalizedString("FILTER_CHOOSE_PERSON", comment: "Title of the list that chooses the person whose messages to search.") + "…"
            content.image = UIImage(systemName: "person")
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func apply(_ suggestion: Suggestion) {
        guard let filterBar else { return }
        switch suggestion {
        case .links: filterBar.setContent(.link)
        case .photos: filterBar.setContent(.photo)
        case .files: filterBar.setContent(.file)
        case .inChat: filterBar.chooseChat()
        case .from: filterBar.choosePerson()
        }
    }

    /// The index marks matches with tags; the list shows plain text.
    static func plainSnippet(_ snippet: String) -> String {
        snippet
            .replacingOccurrences(of: "<\(FullTextSearchIndexer.matchTag)>", with: "")
            .replacingOccurrences(of: "</\(FullTextSearchIndexer.matchTag)>", with: "")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if showsSuggestions {
            return suggestionCell(Suggestion.allCases[indexPath.row], at: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "result", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.imageProperties.tintColor = .Signal.accent
        switch sections[indexPath.section].results[indexPath.row] {
        case .message(let threadId, _, let snippet, let timestamp):
            content.text = chatNames[threadId]
            content.secondaryText = IvyFind.dateText(timestamp) + " · " + Self.plainSnippet(snippet)
            content.image = UIImage(systemName: "bubble.left")
        case .task(let task):
            content.text = task.title
            content.secondaryText = IvyTaskUI.subtitle(for: task, listName: nil)
            content.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
        case .event(let event):
            content.text = event.title
            content.secondaryText = DateFormatter.localizedString(from: event.startAt, dateStyle: .medium, timeStyle: event.isAllDay ? .none : .short)
            content.image = UIImage(systemName: "calendar")
        case .chatNote(let chat, let text):
            content.text = chatNames[chat.rawValue]
            content.secondaryText = text
            content.image = UIImage(systemName: "note.text")
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if showsSuggestions {
            apply(Suggestion.allCases[indexPath.row])
            return
        }
        switch sections[indexPath.section].results[indexPath.row] {
        case .message(let threadId, let messageId, _, _):
            IvyFind.showMessage(threadUniqueId: threadId, messageUniqueId: messageId, from: self)
        case .task(let task):
            ivyPresentTaskEditor(task, isNew: false)
        case .event(let event):
            ivyPresentEventEditor(event, isNew: false)
        case .chatNote(let chat, _):
            navigationController?.pushViewController(IvyChatNoteViewController(chat: chat), animated: true)
        }
    }
}

// MARK: - Library

/// Every link, photo and file from all chats, newest first.
final class IvyLibraryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private static let limit = 300

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let kindControl = UISegmentedControl()
    private var filterBar: IvyFilterBar?
    private var items = [IvyLibrary.Item]()
    private var chatNames = [String: String]()
    private var loadGeneration = 0

    private var kind: IvyLibrary.Kind {
        IvyLibrary.Kind.allCases[max(kindControl.selectedSegmentIndex, 0)]
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func title(for kind: IvyLibrary.Kind) -> String {
        switch kind {
        case .links: return IvyLocalizedString("LIBRARY_LINKS", comment: "Library section with every link from all chats.")
        case .photos: return IvyLocalizedString("LIBRARY_PHOTOS", comment: "Library section with every photo and video from all chats.")
        case .files: return IvyLocalizedString("LIBRARY_FILES", comment: "Library section with every file from all chats.")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyFind.libraryTitle
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.dismiss(animated: true) }
        for (index, kind) in IvyLibrary.Kind.allCases.enumerated() {
            kindControl.insertSegment(withTitle: Self.title(for: kind), at: index, animated: false)
        }
        kindControl.selectedSegmentIndex = 0
        kindControl.addAction(UIAction { [weak self] _ in self?.load() }, for: .valueChanged)
        navigationItem.titleView = kindControl
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "item")

        tableView.dataSource = self
        tableView.delegate = self

        // The filters stay in view above the list.
        let bar = IvyFilterBar(showsContent: false, presenter: self) { [weak self] _ in self?.load() }
        filterBar = bar
        navigationItem.rightBarButtonItems = (navigationItem.rightBarButtonItems ?? []) + [bar.barButtonItem]
        let stack = UIStackView(arrangedSubviews: [bar, tableView])
        stack.axis = .vertical
        view.backgroundColor = .Signal.groupedBackground
        view.addSubview(stack)
        stack.autoPinEdge(toSuperviewSafeArea: .top)
        stack.autoPinEdge(toSuperviewEdge: .leading)
        stack.autoPinEdge(toSuperviewEdge: .trailing)
        stack.autoPinEdge(toSuperviewEdge: .bottom)
        load()
    }

    private func load() {
        loadGeneration += 1
        let generation = loadGeneration
        let kind = self.kind
        let filter = filterBar?.filter ?? IvySearchFilter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            let (items, names) = SSKEnvironment.shared.databaseStorageRef.read { tx in
                let items = IvyLibrary.items(kind: kind, filter: filter, limit: Self.limit, tx: tx)
                var names = [String: String]()
                for item in items where names[item.threadUniqueId] == nil {
                    names[item.threadUniqueId] = IvyFind.chatName(threadUniqueId: item.threadUniqueId, tx: tx)
                }
                return (items, names)
            }
            DispatchQueue.main.async {
                guard let self, generation == self.loadGeneration else { return }
                self.items = items
                self.chatNames = names
                self.tableView.reloadData()
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(items.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
        guard !items.isEmpty else {
            var content = UIListContentConfiguration.cell()
            content.text = IvyLocalizedString("LIBRARY_EMPTY", comment: "Shown in the library when nothing matches.")
            content.textProperties.color = .Signal.secondaryLabel
            cell.contentConfiguration = content
            cell.accessoryType = .none
            cell.selectionStyle = .none
            return cell
        }
        let item = items[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.imageProperties.tintColor = .Signal.accent
        let place = (chatNames[item.threadUniqueId] ?? "") + " · " + IvyFind.dateText(item.timestamp)
        switch item.kind {
        case .links:
            content.text = item.url?.host ?? item.title
            content.secondaryText = item.title + "\n" + place
            content.secondaryTextProperties.numberOfLines = 3
            content.image = UIImage(systemName: "link")
        case .photos:
            content.text = item.title.nilIfEmpty ?? Self.title(for: .photos)
            content.secondaryText = place
            content.image = UIImage(systemName: "photo")
        case .files:
            content.text = item.title.nilIfEmpty ?? Self.title(for: .files)
            content.secondaryText = place
            content.image = UIImage(systemName: "doc")
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < items.count else { return }
        let item = items[indexPath.row]
        if let url = item.url {
            UIApplication.shared.open(url)
        } else {
            IvyFind.showMessage(threadUniqueId: item.threadUniqueId, messageUniqueId: item.messageUniqueId, from: self)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.row < items.count else { return nil }
        let item = items[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            var actions = [UIAction]()
            if let url = item.url {
                actions.append(UIAction(title: IvyLocalizedString("LIBRARY_OPEN_LINK", comment: "Action that opens a link from the library."), image: UIImage(systemName: "safari")) { _ in
                    UIApplication.shared.open(url)
                })
                actions.append(UIAction(title: IvyLocalizedString("LIBRARY_COPY_LINK", comment: "Action that copies a link from the library."), image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.url = url
                })
            }
            actions.append(UIAction(title: IvyLocalizedString("LIBRARY_SHOW_IN_CHAT", comment: "Action that shows a link, photo or file in its chat."), image: UIImage(systemName: "bubble.left")) { _ in
                guard let self else { return }
                IvyFind.showMessage(threadUniqueId: item.threadUniqueId, messageUniqueId: item.messageUniqueId, from: self)
            })
            return UIMenu(children: actions)
        })
    }
}

// MARK: - Entry points

extension ChatListViewController {

    /// "Search Everything" and "Library" for the profile menu.
    func ivyFindMenuActions() -> [UIAction] {
        [
            UIAction(title: IvyFind.searchTitle, image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                guard let self else { return }
                IvyFind.presentSearch(from: self)
            },
            UIAction(title: IvyFind.libraryTitle, image: UIImage(systemName: "books.vertical")) { [weak self] _ in
                guard let self else { return }
                IvyFind.presentLibrary(from: self)
            },
        ]
    }
}

extension ConversationSplitViewController {

    @objc
    func ivySearchEverything() {
        IvyFind.presentSearch(from: self)
    }

    @objc
    func ivyShowLibrary() {
        IvyFind.presentLibrary(from: self)
    }
}
