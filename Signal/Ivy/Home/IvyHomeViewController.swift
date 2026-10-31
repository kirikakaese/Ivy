//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Home: a greeting, quick actions and what's next, then important unread
/// messages as chat rows, open tasks, the other lists, and unread chats by
/// folder. Cards use Ivy's pastel tones, like the calendar.
final class IvyHomeViewController: UIViewController, HomeTabViewController, UITableViewDataSource, UITableViewDelegate {

    /// Open tasks shown at most.
    static let maxTasks = 6
    /// Starred messages shown at most.
    static let maxStars = 3
    /// Important messages shown at most.
    static let maxImportantMessages = 8
    static let maxWaitingQuestions = 5
    static let maxDrafts = 5
    /// Upcoming tasks reach this many days ahead.
    static let upcomingTaskDays = 7

    private struct ImportantRow {
        let message: IvyImportantMessage
        let thread: TSThread
        let chatName: String
        /// Who wrote it, in group chats.
        let sender: String?
        let text: String
        let date: Date
    }

    private struct FolderChip {
        let folder: ChatFolder
        let unreadCount: Int
        let color: UIColor
    }

    private enum Row {
        case task(IvyTask, listName: String?)
        case important(ImportantRow)
        case folders([FolderChip])
        case star(IvyStar, chatName: String)
        case scheduled(IvyScheduledMessage, chatName: String)
        case waiting(IvyWaitingQuestion, chatName: String)
        case draft(IvyDraft, chatName: String)
        case note(String)
        case link(String, action: () -> Void)
    }

    private struct Section {
        let title: String
        let rows: [Row]
        /// "All", on the trailing side of the heading.
        var action: (() -> Void)?
    }

    /// Scrolled to the top when Home's tab is chosen again.
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let header = IvyHomeHeaderView()
    private var sections: [Section] = []
    private var needsReload = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("HOME_TITLE", comment: "Title of the Home section with today's agenda, tasks and important messages.")
        // The greeting below takes the place of a title in the bar.
        navigationItem.title = ""
        view.backgroundColor = .Signal.groupedBackground

        header.quickActions = quickActions()
        header.onOpenNextUp = { [weak self] item in
            guard let self else { return }
            if let item {
                open(item)
            } else {
                homeTabBarController?.selectedHomeTab = .calendar
            }
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        tableView.register(IvyImportantCell.self, forCellReuseIdentifier: IvyImportantCell.reuseIdentifier)
        tableView.register(IvyFolderChipsCell.self, forCellReuseIdentifier: IvyFolderChipsCell.reuseIdentifier)
        tableView.register(IvySectionHeaderView.self, forHeaderFooterViewReuseIdentifier: IvySectionHeaderView.reuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.sectionHeaderTopPadding = 0
        tableView.estimatedSectionHeaderHeight = 52
        tableView.tableHeaderView = header
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        for name in [
            IvyTaskManager.tasksDidChange,
            IvyEventManager.eventsDidChange,
            IvyReminderManager.remindersDidChange,
            IvyStarManager.starsDidChange,
            IvyScheduledSender.scheduledDidChange,
            ChatFolderManager.foldersDidChange,
            IvyHiddenChats.hiddenChatsDidChange,
            IvyDataStore.dataDidChange,
            UIApplication.significantTimeChangeNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(setNeedsReload), name: name, object: nil)
        }
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ivyUpdateProfileButton()
        reload()
    }

    /// The header sizes itself to the table's width.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        let height = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        ).height
        if header.frame.size != CGSize(width: width, height: height) {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = header
        }
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

    private func quickActions() -> [IvyHomeHeaderView.QuickAction] {
        [
            .init(
                title: IvyLocalizedString("HOME_NEW_MESSAGE", comment: "Quick action on Home that starts a new message."),
                systemImage: "bubble.left",
            ) { [weak self] in
                self?.homeTabBarController?.selectedHomeTab = .chatList
                self?.homeTabBarController?.chatListViewController.showNewConversationView()
            },
            .init(
                title: IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task."),
                systemImage: "checkmark.circle",
            ) { [weak self] in
                self?.ivyPresentTaskEditor(IvyTask(title: ""), isNew: true)
            },
            .init(
                title: IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event."),
                systemImage: "calendar",
            ) { [weak self] in
                self?.ivyPresentEventEditor(IvyLinkHandler.newEvent(), isNew: true)
            },
            .init(
                title: IvyLocalizedString("HOME_NEW_REMINDER", comment: "Quick action on Home that sets a reminder for a chat."),
                systemImage: "bell",
            ) { [weak self] in
                self?.presentReminderChatChooser()
            },
        ]
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
        updateHeader()
        var sections = [Section]()
        if let important = importantSection() {
            sections.append(important)
        }
        sections.append(tasksSection())
        if let scheduled = scheduledSection() {
            sections.append(scheduled)
        }
        if let waiting = waitingSection() {
            sections.append(waiting)
        }
        if let drafts = draftsSection() {
            sections.append(drafts)
        }
        if let starred = starredSection() {
            sections.append(starred)
        }
        if let folders = foldersSection() {
            sections.append(folders)
        }
        self.sections = sections
        tableView.reloadData()
        view.setNeedsLayout()
    }

    /// The greeting and what's next today, or first thing tomorrow.
    private func updateHeader() {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? now
        let items = IvyCalendar.items(
            events: IvyEventManager.shared.allEvents(),
            tasks: [],
            reminders: IvyReminderManager.shared.openReminders(),
            in: DateInterval(start: start, end: end),
            calendar: calendar,
        )
        let chatNames = reminderChatNames()
        header.update(now: now, nextUp: Self.nextUp(items, now: now, calendar: calendar)) { [weak self] item in
            self?.title(for: item, chatNames: chatNames) ?? ""
        }
    }

    /// The item happening now or next, today or tomorrow, and the one after
    /// it on the same day. All-day items are left out.
    static func nextUp(_ items: [IvyCalendarItem], now: Date, calendar: Calendar = .current) -> (item: IvyCalendarItem, following: IvyCalendarItem?)? {
        let timed = items
            .filter { !$0.isAllDay && max($0.start, $0.end) > now }
            .sorted { $0.start < $1.start }
        guard let first = timed.first else {
            return nil
        }
        let following = timed.dropFirst().first { calendar.isDate($0.start, inSameDayAs: first.start) }
        return (first, following)
    }

    private func title(for item: IvyCalendarItem, chatNames: [IvyChatReference: String]) -> String {
        switch item.kind {
        case .event(let event): return event.title
        case .task(let task): return task.title
        case .reminder(let reminder):
            return chatNames[reminder.chat] ?? IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
        }
    }

    private func open(_ item: IvyCalendarItem) {
        switch item.kind {
        case .event(let event): ivyPresentEventEditor(event, isNew: false)
        case .task(let task): ivyPresentTaskEditor(task, isNew: false)
        case .reminder(let reminder): IvyReminderActionHandler.open(reminderId: reminder.id)
        }
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
        rows.append(.link(IvyWeeklyReviewViewController.title) { [weak self] in
            self?.ivyPresentWeeklyReview()
        })
        return Section(title: IvyTaskUI.tasksTitle, rows: rows) { [weak self] in
            self?.ivyPresentTasks()
        }
    }

    /// The next messages scheduled to be sent, when there are any.
    private func scheduledSection() -> Section? {
        let pending = IvyScheduledUI.pending()
        guard !pending.isEmpty else {
            return nil
        }
        let rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            pending.prefix(Self.maxStars).map { message in
                let name = message.chat.thread(tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                }
                return .scheduled(message, chatName: name ?? "")
            }
        }
        return Section(title: IvyScheduledUI.title, rows: rows) { [weak self] in
            self?.presentFormSheet(OWSNavigationController(rootViewController: IvyScheduledMessagesViewController()), animated: true)
        }
    }

    /// The newest starred messages, when there are any.
    private func starredSection() -> Section? {
        let stars = IvyStarManager.shared.allStars()
        guard !stars.isEmpty else {
            return nil
        }
        let rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            stars.prefix(Self.maxStars).map { star in
                let name = star.message.chat.thread(tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                }
                return .star(star, chatName: name ?? "")
            }
        }
        return Section(title: IvyStarredViewController.title, rows: rows) { [weak self] in
            self?.presentFormSheet(OWSNavigationController(rootViewController: IvyStarredViewController()), animated: true)
        }
    }

    /// Questions the user hasn't answered yet.
    private func waitingSection() -> Section? {
        let rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            var excluded = IvySnoozedChats.shared.threadIds(tx: tx)
            if !IvyHiddenChats.shared.isRevealed {
                excluded.formUnion(IvyHiddenChats.shared.threadIds(tx: tx))
            }
            return IvyWaitingOnYou.find(excludedThreadIds: excluded, limit: Self.maxWaitingQuestions, tx: tx).compactMap { question in
                guard let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: question.threadUniqueId, tx: tx) else {
                    return nil
                }
                return .waiting(question, chatName: SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx))
            }
        }
        guard !rows.isEmpty else {
            return nil
        }
        return Section(title: Self.waitingTitle, rows: rows)
    }

    /// Messages started in chats and not sent yet.
    private func draftsSection() -> Section? {
        let rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            IvyDrafts.all(limit: Self.maxDrafts, tx: tx).compactMap { draft in
                guard let thread = DependenciesBridge.shared.threadStore.fetchThread(uniqueId: draft.threadUniqueId, tx: tx) else {
                    return nil
                }
                if IvyHiddenChats.shared.isHidden(thread: thread), !IvyHiddenChats.shared.isRevealed {
                    return nil
                }
                return .draft(draft, chatName: SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx))
            }
        }
        guard !rows.isEmpty else {
            return nil
        }
        return Section(title: IvyLocalizedString("HOME_DRAFTS", comment: "Title of the section on Home with unsent messages."), rows: rows)
    }

    static var waitingTitle: String {
        IvyLocalizedString("HOME_WAITING_ON_YOU", comment: "Title of the section on Home with questions the user hasn't answered.")
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
                var sender: String?
                if thread.isGroupThread, let incoming = message as? TSIncomingMessage {
                    sender = SSKEnvironment.shared.contactManagerRef.displayName(for: incoming.authorAddress, tx: tx).resolvedValue()
                }
                return ImportantRow(
                    message: important,
                    thread: thread,
                    chatName: SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx),
                    sender: sender,
                    text: String(text.prefix(200)),
                    date: Date(millisecondsSince1970: message.timestamp),
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
        let extras = ChatFolderExtras.fetchAll(store: IvyData.shared?.store)
        let chips: [FolderChip] = folders.compactMap { folder in
            guard let count = counts[folder.id], count > 0 else { return nil }
            let color = extras[folder.id]?.color.map { ChatFolderBar.uiColor(for: $0) } ?? .Signal.accent
            return FolderChip(folder: folder, unreadCount: count, color: color)
        }
        guard !chips.isEmpty else {
            return nil
        }
        return Section(
            title: IvyLocalizedString("HOME_UNREAD_BY_FOLDER", comment: "Header on Home of the folders with unread chats."),
            rows: [.folders(chips)],
        )
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: IvySectionHeaderView.reuseIdentifier) as? IvySectionHeaderView
        let item = sections[section]
        view?.cardInset = tableView.layoutMargins.left
        view?.configure(
            title: item.title,
            actionTitle: item.action == nil ? nil : IvyLocalizedString("HOME_SECTION_ALL", comment: "Button beside a heading on Home that opens the whole list."),
            action: item.action,
        )
        return view
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    /// Important messages look like chat rows; the others have an icon in
    /// Ivy's colour, a title and a line of detail.
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .important(let row):
            let cell = tableView.dequeueReusableCell(withIdentifier: IvyImportantCell.reuseIdentifier, for: indexPath)
            (cell as? IvyImportantCell)?.configure(
                thread: row.thread,
                chatName: row.chatName,
                sender: row.sender,
                text: row.text,
                date: row.date,
                reason: Self.title(for: row.message.reason),
                tone: Self.tone(for: row.message.reason),
            )
            return cell
        case .folders(let chips):
            let cell = tableView.dequeueReusableCell(withIdentifier: IvyFolderChipsCell.reuseIdentifier, for: indexPath)
            (cell as? IvyFolderChipsCell)?.configure(chips.map { chip in
                (
                    title: ChatFolderBar.title(for: chip.folder),
                    count: chip.unreadCount,
                    color: chip.color,
                    action: { [weak self] in
                        guard let tabs = self?.homeTabBarController else { return }
                        tabs.selectedHomeTab = .chatList
                        tabs.chatListViewController.ivySelectChatFolder(chip.folder)
                    },
                )
            })
            return cell
        default:
            break
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.imageProperties.tintColor = .Signal.accent
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default

        switch sections[indexPath.section].rows[indexPath.row] {
        case .task(let task, let listName):
            content.text = task.title
            content.secondaryText = IvyTaskUI.subtitle(for: task, listName: listName)
            content.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
            content.imageProperties.tintColor = .Signal.secondaryLabel
            cell.accessoryType = .none
            if task.isOverdue(at: Date()) {
                content.secondaryTextProperties.color = IvyTone.red.strong
            }
        case .important, .folders:
            break
        case .star(let star, let chatName):
            content.text = chatName
            content.secondaryText = star.quote
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: "star.fill")
        case .draft(let draft, let chatName):
            content.text = chatName
            content.secondaryText = draft.text
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: "square.and.pencil")
        case .waiting(let question, let chatName):
            content.text = chatName
            content.secondaryText = question.text
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: "questionmark.bubble")
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
        case .task(let task, _):
            ivyPresentTaskEditor(task, isNew: false)
        case .important(let row):
            SignalApp.shared.presentConversationForThread(
                threadUniqueId: row.message.threadUniqueId,
                focusMessageId: row.message.messageUniqueId,
                animated: true,
            )
        case .folders:
            break
        case .star(let star, _):
            IvyStarredViewController.open(star.message, from: self)
        case .draft(let draft, _):
            SignalApp.shared.presentConversationForThread(threadUniqueId: draft.threadUniqueId, animated: true)
        case .waiting(let question, _):
            SignalApp.shared.presentConversationForThread(
                threadUniqueId: question.threadUniqueId,
                focusMessageId: question.messageUniqueId,
                animated: true,
            )
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
        case .task(let task, _):
            let date = task.dueAt ?? Date()
            return IvyCalendarItem(kind: .task(task), start: date, end: date, isAllDay: task.isAllDay)
        case .important, .folders, .star, .scheduled, .waiting, .draft, .note, .link:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if case .draft(let draft, _) = sections[indexPath.section].rows[indexPath.row] {
            return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
                UIMenu(children: [UIAction(title: IvyPlanMessageUI.planTitle, image: UIImage(systemName: "clock.badge")) { _ in
                    self?.planDraft(draft)
                }])
            })
        }
        if let question = waitingQuestion(at: indexPath) {
            return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
                UIMenu(children: [UIAction(title: Self.dismissWaitingTitle, image: UIImage(systemName: "checkmark")) { _ in
                    self?.dismissWaiting(question)
                }])
            })
        }
        guard let item = calendarItem(at: indexPath) else {
            return nil
        }
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: IvyCalendarUI.menuActions(for: item))
        })
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if case .draft(let draft, _) = sections[indexPath.section].rows[indexPath.row] {
            let action = UIContextualAction(
                style: .destructive,
                title: IvyLocalizedString("HOME_DRAFT_DISCARD", comment: "Action that throws away an unsent message on Home."),
            ) { [weak self] _, _, completion in
                SSKEnvironment.shared.databaseStorageRef.write { tx in IvyDrafts.discard(threadUniqueId: draft.threadUniqueId, tx: tx) }
                self?.reload()
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [action])
        }
        if let question = waitingQuestion(at: indexPath) {
            let action = UIContextualAction(style: .normal, title: Self.dismissWaitingTitle) { [weak self] _, _, completion in
                self?.dismissWaiting(question)
                completion(true)
            }
            action.backgroundColor = .Signal.accent
            return UISwipeActionsConfiguration(actions: [action])
        }
        return calendarItem(at: indexPath).map { IvyCalendarUI.swipeActions(for: $0) }
    }

    /// Sends a draft at a chosen time, and clears it from its chat.
    private func planDraft(_ draft: IvyDraft) {
        let chat = SSKEnvironment.shared.databaseStorageRef.read { tx in
            DependenciesBridge.shared.threadStore.fetchThread(uniqueId: draft.threadUniqueId, tx: tx).flatMap(IvyChatReference.init(thread:))
        }
        ivyPresentPlanMessage(chat: chat, text: draft.text, sendAt: IvyPlanMessageUI.suggestedTime(on: Date())) { [weak self] in
            SSKEnvironment.shared.databaseStorageRef.write { tx in IvyDrafts.discard(threadUniqueId: draft.threadUniqueId, tx: tx) }
            self?.reload()
        }
    }

    private func waitingQuestion(at indexPath: IndexPath) -> IvyWaitingQuestion? {
        if case .waiting(let question, _) = sections[indexPath.section].rows[indexPath.row] {
            return question
        }
        return nil
    }

    private static var dismissWaitingTitle: String {
        IvyLocalizedString("HOME_WAITING_DISMISS", comment: "Action that removes an unanswered question from Home without answering it.")
    }

    private func dismissWaiting(_ question: IvyWaitingQuestion) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in IvyWaitingOnYou.dismiss(question, tx: tx) }
        reload()
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

    /// The tag colour for why a message is important.
    static func tone(for reason: IvyImportantMessage.Reason) -> IvyTone {
        switch reason {
        case .reminder: return .brown
        case .mention: return .blue
        case .reply: return .brown
        case .importantChat: return .green
        case .pinnedChat: return .green
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
