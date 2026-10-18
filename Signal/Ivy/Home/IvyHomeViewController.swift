//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Home: quick actions, today's agenda, open tasks, important unread
/// messages and unread chats by folder.
final class IvyHomeViewController: OWSTableViewController2 {

    /// Open tasks shown at most.
    static let maxTasks = 6
    /// Important messages shown at most.
    static let maxImportantMessages = 8
    /// Upcoming tasks reach this many days ahead.
    static let upcomingTaskDays = 7

    private var needsReload = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("HOME_TITLE", comment: "Title of the Home section with today's agenda, tasks and important messages.")
        for name in [
            IvyTaskManager.tasksDidChange,
            IvyEventManager.eventsDidChange,
            IvyReminderManager.remindersDidChange,
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

    // MARK: - Contents

    private func reload() {
        let contents = OWSTableContents(title: title)
        contents.add(quickActionsSection())
        contents.add(todaySection())
        contents.add(tasksSection())
        if let importantSection = importantSection() {
            contents.add(importantSection)
        }
        if let foldersSection = foldersSection() {
            contents.add(foldersSection)
        }
        self.contents = contents
    }

    // MARK: Quick actions

    private func quickActionsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.hasBackground = false
        let buttons = [
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
                let calendar = Calendar.current
                let start = calendar.dateInterval(of: .hour, for: Date())?.end ?? Date()
                self?.ivyPresentEventEditor(IvyEvent(title: "", startAt: start, endAt: start.addingTimeInterval(60 * 60)), isNew: true)
            },
            quickAction(
                title: IvyLocalizedString("HOME_NEW_REMINDER", comment: "Quick action on Home that sets a reminder for a chat."),
                systemImage: "bell.badge",
            ) { [weak self] in
                self?.presentReminderChatChooser()
            },
        ]
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        section.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            cell.backgroundColor = .clear
            cell.contentView.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
                stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            ])
            return cell
        }))
        return section
    }

    private func quickAction(title: String, systemImage: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(systemName: systemImage)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        var attributedTitle = AttributedString(title)
        attributedTitle.font = UIFont.dynamicTypeCaption1Clamped
        configuration.attributedTitle = attributedTitle
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.baseForegroundColor = .Signal.accent
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 4, bottom: 10, trailing: 4)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = title
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

    // MARK: Today

    private func todaySection() -> OWSTableSection {
        let calendar = Calendar.current
        let today = calendar.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 86_400)
        let items = IvyCalendar.items(
            events: IvyEventManager.shared.allEvents(),
            tasks: [],
            reminders: IvyReminderManager.shared.openReminders(),
            in: today,
            calendar: calendar,
        )
        let section = OWSTableSection()
        section.headerTitle = IvyCalendarUI.dayTitle(today.start)
        if items.isEmpty {
            section.add(Self.textItem(IvyLocalizedString("HOME_NOTHING_TODAY", comment: "Shown on Home when there are no events or reminders today.")))
        }
        let chatNames = reminderChatNames()
        for item in items {
            section.add(agendaItem(item, chatNames: chatNames))
        }
        section.add(.disclosureItem(
            withText: IvyLocalizedString("HOME_OPEN_CALENDAR", comment: "Item on Home that opens the calendar."),
            textColor: .Signal.accent,
        ) { [weak self] in
            self?.homeTabBarController?.selectedHomeTab = .calendar
        })
        return section
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

    private func agendaItem(_ item: IvyCalendarItem, chatNames: [IvyChatReference: String]) -> OWSTableItem {
        let title: String
        let image: String
        switch item.kind {
        case .event(let event):
            title = event.title
            image = "calendar"
        case .task(let task):
            title = task.title
            image = "checklist"
        case .reminder(let reminder):
            title = chatNames[reminder.chat] ?? IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
            image = "bell"
        }
        return OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                var content = UIListContentConfiguration.valueCell()
                content.text = title
                content.secondaryText = IvyCalendarUI.timeText(for: item)
                content.image = UIImage(systemName: image)
                content.imageProperties.tintColor = .Signal.accent
                cell.contentConfiguration = content
                return cell
            },
            actionBlock: { [weak self] in
                self?.open(item)
            },
        )
    }

    private func open(_ item: IvyCalendarItem) {
        switch item.kind {
        case .event(let event):
            ivyPresentEventEditor(event, isNew: false)
        case .task(let task):
            ivyPresentTaskEditor(task, isNew: false)
        case .reminder(let reminder):
            IvyReminderActionHandler.open(reminderId: reminder.id)
        }
    }

    // MARK: Tasks

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

    private func tasksSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = IvyTaskUI.tasksTitle
        let now = Date()
        let lists = Dictionary(uniqueKeysWithValues: IvyTaskManager.shared.lists().map { ($0.id, $0.name) })
        let tasks = Self.homeTasks(IvyTaskManager.shared.allTasks(), now: now)
        if tasks.isEmpty {
            section.add(Self.textItem(IvyLocalizedString("TASKS_EMPTY_TITLE", comment: "Title shown in the list of tasks when there are no open tasks.")))
        }
        for task in tasks {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    let row = IvyTaskRowView(task: task, listName: task.listId.flatMap { lists[$0] }, now: now)
                    cell.contentView.addSubview(row)
                    row.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        row.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                        row.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
                        row.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                        row.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    ])
                    return cell
                },
                actionBlock: { [weak self] in
                    self?.ivyPresentTaskEditor(task, isNew: false)
                },
            ))
        }
        section.add(.disclosureItem(
            withText: IvyLocalizedString("HOME_ALL_TASKS", comment: "Item on Home that opens the list of all tasks."),
            textColor: .Signal.accent,
        ) { [weak self] in
            self?.ivyPresentTasks()
        })
        return section
    }

    // MARK: Important messages

    private struct ImportantRow {
        let message: IvyImportantMessage
        let chatName: String
        let text: String
    }

    private func importantSection() -> OWSTableSection? {
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
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("HOME_IMPORTANT", comment: "Header on Home of important unread messages.")
        for row in rows {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    var content = UIListContentConfiguration.subtitleCell()
                    content.text = row.chatName
                    content.secondaryText = Self.title(for: row.message.reason) + " · " + row.text
                    content.secondaryTextProperties.numberOfLines = 2
                    content.secondaryTextProperties.color = .Signal.secondaryLabel
                    content.image = UIImage(systemName: Self.imageName(for: row.message.reason))
                    content.imageProperties.tintColor = .Signal.accent
                    cell.contentConfiguration = content
                    return cell
                },
                actionBlock: {
                    SignalApp.shared.presentConversationForThread(
                        threadUniqueId: row.message.threadUniqueId,
                        focusMessageId: row.message.messageUniqueId,
                        animated: true,
                    )
                },
            ))
        }
        return section
    }

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

    // MARK: Folders

    private func foldersSection() -> OWSTableSection? {
        let (folders, chats) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (ChatFolderManager.shared.folders(tx: tx), ChatFolderChats.inboxChats(tx: tx))
        }
        let counts = ChatFolderChats.unreadCounts(folders: folders, chats: chats)
        let unreadFolders = folders.filter { (counts[$0.id] ?? 0) > 0 }
        guard !unreadFolders.isEmpty else {
            return nil
        }
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("HOME_UNREAD_BY_FOLDER", comment: "Header on Home of the folders with unread chats.")
        for folder in unreadFolders {
            let count = counts[folder.id] ?? 0
            section.add(.disclosureItem(
                withText: ChatFolderBar.title(for: folder),
                accessoryText: count.formatted(),
            ) { [weak self] in
                guard let tabs = self?.homeTabBarController else { return }
                tabs.selectedHomeTab = .chatList
                tabs.chatListViewController.ivySelectChatFolder(folder)
            })
        }
        return section
    }

    // MARK: -

    /// A row of secondary text, for "nothing here" notes.
    private static func textItem(_ text: String) -> OWSTableItem {
        OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none
            var content = UIListContentConfiguration.cell()
            content.text = text
            content.textProperties.color = .Signal.secondaryLabel
            cell.contentConfiguration = content
            return cell
        })
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
