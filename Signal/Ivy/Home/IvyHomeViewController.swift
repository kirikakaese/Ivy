//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Home: quick actions, today's agenda, open tasks, important unread
/// messages and unread chats by folder. It uses the same list style as the
/// calendar, so both pages look alike.
final class IvyHomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    /// Open tasks shown at most.
    static let maxTasks = 6
    /// Starred messages shown at most.
    static let maxStars = 3
    /// Important messages shown at most.
    static let maxImportantMessages = 8
    /// Upcoming tasks reach this many days ahead.
    static let upcomingTaskDays = 7

    private struct ImportantRow {
        let message: IvyImportantMessage
        let chatName: String
        let text: String
    }

    private enum Row {
        case agenda(IvyCalendarItem, title: String)
        case task(IvyTask, listName: String?)
        case important(ImportantRow)
        case folder(ChatFolder, unreadCount: Int)
        case star(IvyStar, chatName: String)
        case scheduled(IvyScheduledMessage, chatName: String)
        case note(String)
        case link(String, action: () -> Void)
    }

    private struct Section {
        let title: String
        let rows: [Row]
    }

    /// Scrolled to the top when Home's tab is chosen again.
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let quickActions = UIStackView()
    private var sections: [Section] = []
    private var needsReload = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("HOME_TITLE", comment: "Title of the Home section with today's agenda, tasks and important messages.")
        view.backgroundColor = .Signal.groupedBackground

        quickActions.axis = .horizontal
        quickActions.distribution = .fillEqually
        quickActions.alignment = .fill
        quickActions.spacing = 8
        for button in quickActionButtons() {
            quickActions.addArrangedSubview(button)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        tableView.backgroundColor = .clear

        // The same frame as the calendar: controls on top, then the list.
        let stack = UIStackView(arrangedSubviews: [quickActions, tableView])
        stack.axis = .vertical
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        for name in [
            IvyTaskManager.tasksDidChange,
            IvyEventManager.eventsDidChange,
            IvyReminderManager.remindersDidChange,
            IvyStarManager.starsDidChange,
            IvyScheduledSender.scheduledDidChange,
            ChatFolderManager.foldersDidChange,
            UIApplication.significantTimeChangeNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(setNeedsReload), name: name, object: nil)
        }
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    /// Reloads soon, once, after a burst of changes.
    @objc
    private func setNeedsReload() {
        guard !needsReload else {
            return
        }
        needsReload = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            needsReload = false
            if view.window != nil {
                reload()
            }
        }
    }

    // MARK: - Quick actions

    private func quickActionButtons() -> [UIButton] {
        [
            quickAction(
                title: IvyLocalizedString("HOME_NEW_MESSAGE", comment: "Quick action on Home that starts a new message."),
                systemImage: "square.and.pencil",
            ) { [weak self] in
                self?.homeTabBarController?.selectedHomeTab = .chatList
                self?.homeTabBarController?.chatListViewController.showNewConversationView()
            },
            quickAction(
                title: IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task."),
                systemImage: "checklist",
            ) { [weak self] in
                self?.ivyPresentTaskEditor(IvyTask(title: ""), isNew: true)
            },
            quickAction(
                title: IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event."),
                systemImage: "calendar.badge.plus",
            ) { [weak self] in
                self?.ivyPresentEventEditor(IvyLinkHandler.newEvent(), isNew: true)
            },
            quickAction(
                title: IvyLocalizedString("HOME_NEW_REMINDER", comment: "Quick action on Home that sets a reminder for a chat."),
                systemImage: "bell.badge",
            ) { [weak self] in
                self?.presentReminderChatChooser()
            },
        ]
    }

    /// A tile like the calendar's mode switcher: icon above a title that
    /// wraps instead of being cut off.
    private func quickAction(title: String, systemImage: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        // The icon keeps Ivy's color; the title stays readable.
        configuration.image = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium))?
            .withTintColor(.Signal.accent, renderingMode: .alwaysOriginal)
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        var attributedTitle = AttributedString(title)
        attributedTitle.font = UIFont.dynamicTypeFootnoteClamped.medium()
        configuration.attributedTitle = attributedTitle
        configuration.titleAlignment = .center
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.baseForegroundColor = .Signal.label
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 6, bottom: 12, trailing: 6)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = title
        button.toolTip = title
        return button
    }

    private func presentReminderChatChooser() {
        let chooser = IvyChatChooserViewController(preferredChat: nil) { [weak self] thread in
            guard let chat = IvyChatReference(thread: thread) else { return }
            self?.ivyPresentRemindMe(chat: chat, message: nil)
        }
        chooser.title = IvyLocalizedString("HOME_NEW_REMINDER", comment: "Quick action on Home that sets a reminder for a chat.")
        presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
    }

    // MARK: - Contents

    private func reload() {
        var sections = [todaySection(), tasksSection()]
        if let scheduled = scheduledSection() {
            sections.append(scheduled)
        }
        if let starred = starredSection() {
            sections.append(starred)
        }
        if let important = importantSection() {
            sections.append(important)
        }
        if let folders = foldersSection() {
            sections.append(folders)
        }
        self.sections = sections
        tableView.reloadData()
    }

    private func todaySection() -> Section {
        let calendar = Calendar.current
        let today = calendar.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 86_400)
        let items = IvyCalendar.items(
            events: IvyEventManager.shared.allEvents(),
            tasks: [],
            reminders: IvyReminderManager.shared.openReminders(),
            in: today,
            calendar: calendar,
        )
        let chatNames = reminderChatNames()
        var rows: [Row] = items.map { item in
            let title: String
            switch item.kind {
            case .event(let event): title = event.title
            case .task(let task): title = task.title
            case .reminder(let reminder):
                title = chatNames[reminder.chat] ?? IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
            }
            return .agenda(item, title: title)
        }
        if rows.isEmpty {
            rows.append(.note(IvyLocalizedString("HOME_NOTHING_TODAY", comment: "Shown on Home when there are no events or reminders today.")))
        }
        rows.append(.link(IvyLocalizedString("HOME_OPEN_CALENDAR", comment: "Item on Home that opens the calendar.")) { [weak self] in
            self?.homeTabBarController?.selectedHomeTab = .calendar
        })
        return Section(title: IvyCalendarUI.dayTitle(today.start), rows: rows)
    }

    private func reminderChatNames() -> [IvyChatReference: String] {
        let reminders = IvyReminderManager.shared.openReminders()
        return SSKEnvironment.shared.databaseStorageRef.read { tx in
            var names = [IvyChatReference: String]()
            for reminder in reminders {
                if let thread = reminder.chat.thread(tx: tx) {
                    names[reminder.chat] = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                }
            }
            return names
        }
    }

    /// Open tasks that are overdue or due within the next week, soonest
    /// first, then the ones without a date.
    static func homeTasks(_ tasks: [IvyTask], now: Date, calendar: Calendar = .current) -> [IvyTask] {
        let horizon = calendar.date(byAdding: .day, value: upcomingTaskDays, to: calendar.startOfDay(for: now)) ?? now
        let dated = tasks.filter { task in
            guard !task.isDone, let dueAt = task.dueAt else { return false }
            return dueAt < horizon
        }
        let undated = tasks.filter { !$0.isDone && $0.dueAt == nil }
        return Array((dated + undated).prefix(maxTasks))
    }

    private func tasksSection() -> Section {
        let lists = Dictionary(uniqueKeysWithValues: IvyTaskManager.shared.lists().map { ($0.id, $0.name) })
        var rows: [Row] = Self.homeTasks(IvyTaskManager.shared.allTasks(), now: Date()).map { task in
            .task(task, listName: task.listId.flatMap { lists[$0] })
        }
        if rows.isEmpty {
            rows.append(.note(IvyLocalizedString("TASKS_EMPTY_TITLE", comment: "Title shown in the list of tasks when there are no open tasks.")))
        }
        rows.append(.link(IvyLocalizedString("HOME_ALL_TASKS", comment: "Item on Home that opens the list of all tasks.")) { [weak self] in
            self?.ivyPresentTasks()
        })
        return Section(title: IvyTaskUI.tasksTitle, rows: rows)
    }

    /// The next messages scheduled to be sent, when there are any.
    private func scheduledSection() -> Section? {
        let pending = IvyScheduledUI.pending()
        guard !pending.isEmpty else {
            return nil
        }
        var rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            pending.prefix(Self.maxStars).map { message in
                let name = message.chat.thread(tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                }
                return .scheduled(message, chatName: name ?? "")
            }
        }
        rows.append(.link(IvyLocalizedString("HOME_ALL_SCHEDULED", comment: "Item on Home that opens the list of all scheduled messages.")) { [weak self] in
            self?.presentFormSheet(OWSNavigationController(rootViewController: IvyScheduledMessagesViewController()), animated: true)
        })
        return Section(title: IvyScheduledUI.title, rows: rows)
    }

    /// The newest starred messages, when there are any.
    private func starredSection() -> Section? {
        let stars = IvyStarManager.shared.allStars()
        guard !stars.isEmpty else {
            return nil
        }
        var rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            stars.prefix(Self.maxStars).map { star in
                let name = star.message.chat.thread(tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                }
                return .star(star, chatName: name ?? "")
            }
        }
        rows.append(.link(IvyLocalizedString("HOME_ALL_STARRED", comment: "Item on Home that opens the list of all starred messages.")) { [weak self] in
            self?.presentFormSheet(OWSNavigationController(rootViewController: IvyStarredViewController()), animated: true)
        })
        return Section(title: IvyStarredViewController.title, rows: rows)
    }

    private func importantSection() -> Section? {
        let now = Date()
        let dueReminderMessages = IvyReminderManager.shared.openReminders().filter { $0.isDue(at: now) }.compactMap(\.message)
        let rows: [ImportantRow] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let messages = IvyImportantMessage.find(
                importantChats: IvyHomeSettings.importantChats(tx: tx),
                dueReminderMessages: dueReminderMessages,
                limit: Self.maxImportantMessages,
                tx: tx,
            )
            return messages.compactMap { important in
                guard
                    let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: important.threadUniqueId, tx: tx),
                    let message = TSInteraction.fetchViaCache(uniqueId: important.messageUniqueId, transaction: tx) as? TSMessage
                else {
                    return nil
                }
                let text = message.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? IvyLocalizedString("REMINDER_BODY_MESSAGE", comment: "Body of a reminder notification about a message without text.")
                return ImportantRow(
                    message: important,
                    chatName: SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx),
                    text: String(text.prefix(200)),
                )
            }
        }
        guard !rows.isEmpty else {
            return nil
        }
        return Section(
            title: IvyLocalizedString("HOME_IMPORTANT", comment: "Header on Home of important unread messages."),
            rows: rows.map { .important($0) },
        )
    }

    private func foldersSection() -> Section? {
        let (folders, chats) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (ChatFolderManager.shared.folders(tx: tx), ChatFolderChats.inboxChats(tx: tx))
        }
        let counts = ChatFolderChats.unreadCounts(folders: folders, chats: chats)
        let rows: [Row] = folders.compactMap { folder in
            guard let count = counts[folder.id], count > 0 else { return nil }
            return .folder(folder, unreadCount: count)
        }
        guard !rows.isEmpty else {
            return nil
        }
        return Section(
            title: IvyLocalizedString("HOME_UNREAD_BY_FOLDER", comment: "Header on Home of the folders with unread chats."),
            rows: rows,
        )
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    /// Rows look like the calendar's: an icon in Ivy's color, a title and a
    /// line of detail.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.imageProperties.tintColor = .Signal.accent
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        switch sections[indexPath.section].rows[indexPath.row] {
        case .agenda(let item, let title):
            content.text = title
            content.secondaryText = IvyCalendarUI.timeText(for: item)
            switch item.kind {
            case .event(let event):
                content.image = UIImage(systemName: event.recurrence == nil ? "calendar" : "repeat")
                if !event.location.isEmpty {
                    content.secondaryText = (content.secondaryText ?? "") + " · " + event.location
                }
            case .task(let task):
                content.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
            case .reminder:
                content.image = UIImage(systemName: "bell")
            }
        case .task(let task, let listName):
            content.text = task.title
            content.secondaryText = IvyTaskUI.subtitle(for: task, listName: listName)
            content.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
            if task.isOverdue(at: Date()) {
                content.secondaryTextProperties.color = .Signal.red
            }
        case .important(let row):
            content.text = row.chatName
            content.secondaryText = Self.title(for: row.message.reason) + " · " + row.text
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: Self.imageName(for: row.message.reason))
        case .folder(let folder, let unreadCount):
            content = UIListContentConfiguration.valueCell()
            content.text = ChatFolderBar.title(for: folder)
            content.secondaryText = unreadCount.formatted()
            content.image = UIImage(systemName: "folder")
            content.imageProperties.tintColor = .Signal.accent
        case .star(let star, let chatName):
            content.text = chatName
            content.secondaryText = star.quote
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: "star.fill")
        case .scheduled(let message, let chatName):
            content.text = chatName
            content.secondaryText = IvyScheduledUI.sendTimeText(message.sendAt) + " · " + message.previewText
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: "clock")
        case .note(let text):
            content = UIListContentConfiguration.cell()
            content.text = text
            content.textProperties.color = .Signal.secondaryLabel
            cell.accessoryType = .none
            cell.selectionStyle = .none
        case .link(let title, _):
            content = UIListContentConfiguration.cell()
            content.text = title
            content.textProperties.color = .Signal.accent
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .agenda(let item, _):
            switch item.kind {
            case .event(let event): ivyPresentEventEditor(event, isNew: false)
            case .task(let task): ivyPresentTaskEditor(task, isNew: false)
            case .reminder(let reminder): IvyReminderActionHandler.open(reminderId: reminder.id)
            }
        case .task(let task, _):
            ivyPresentTaskEditor(task, isNew: false)
        case .important(let row):
            SignalApp.shared.presentConversationForThread(
                threadUniqueId: row.message.threadUniqueId,
                focusMessageId: row.message.messageUniqueId,
                animated: true,
            )
        case .folder(let folder, _):
            guard let tabs = homeTabBarController else { return }
            tabs.selectedHomeTab = .chatList
            tabs.chatListViewController.ivySelectChatFolder(folder)
        case .star(let star, _):
            IvyStarredViewController.open(star.message, from: self)
        case .scheduled:
            presentFormSheet(OWSNavigationController(rootViewController: IvyScheduledMessagesViewController()), animated: true)
        case .note:
            break
        case .link(_, let action):
            action()
        }
    }

    /// Events, tasks and reminders can be marked done or deleted from here.
    private func calendarItem(at indexPath: IndexPath) -> IvyCalendarItem? {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .agenda(let item, _):
            return item
        case .task(let task, _):
            let date = task.dueAt ?? Date()
            return IvyCalendarItem(kind: .task(task), start: date, end: date, isAllDay: task.isAllDay)
        case .important, .folder, .star, .scheduled, .note, .link:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = calendarItem(at: indexPath) else {
            return nil
        }
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: IvyCalendarUI.menuActions(for: item))
        })
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        calendarItem(at: indexPath).map { IvyCalendarUI.swipeActions(for: $0) }
    }

    // MARK: -

    static func title(for reason: IvyImportantMessage.Reason) -> String {
        switch reason {
        case .reminder:
            return IvyLocalizedString("HOME_REASON_REMINDER", comment: "Why a message is important on Home: its reminder is due.")
        case .mention:
            return IvyLocalizedString("HOME_REASON_MENTION", comment: "Why a message is important on Home: it mentions the user.")
        case .reply:
            return IvyLocalizedString("HOME_REASON_REPLY", comment: "Why a message is important on Home: it replies to the user.")
        case .importantChat:
            return IvyLocalizedString("HOME_REASON_IMPORTANT_CHAT", comment: "Why a message is important on Home: it's in a chat the user marked as important.")
        case .pinnedChat:
            return IvyLocalizedString("HOME_REASON_PINNED_CHAT", comment: "Why a message is important on Home: it's in a pinned chat.")
        }
    }

    private static func imageName(for reason: IvyImportantMessage.Reason) -> String {
        switch reason {
        case .reminder: return "bell"
        case .mention: return "at"
        case .reply: return "arrowshape.turn.up.left"
        case .importantChat: return "star"
        case .pinnedChat: return "pin"
        }
    }

    private var homeTabBarController: HomeTabBarController? {
        var parent = self.parent
        while let current = parent {
            if let tabs = current as? HomeTabBarController {
                return tabs
            }
            parent = current.parent
        }
        return nil
    }
}

extension IvyHomeViewController: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdateInteractions || databaseChanges.didUpdateThreads else {
            return
        }
        setNeedsReload()
    }

    func databaseChangesDidUpdateExternally() {
        setNeedsReload()
    }

    func databaseChangesDidReset() {
        setNeedsReload()
    }
}
