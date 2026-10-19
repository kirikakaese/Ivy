//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UserNotifications

extension UIViewController {

    func ivyPresentWeeklyReview() {
        presentFormSheet(OWSNavigationController(rootViewController: IvyWeeklyReviewViewController()), animated: true)
    }
}

enum IvyWeeklyReviewUI {

    private static var isStarted = false

    /// Called when the app is ready: keeps the weekly notification scheduled.
    static func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        IvyWeeklyReview.reschedule()
    }

    /// Tapping the weekly notification opens the review.
    @MainActor
    static func handle(_ response: UNNotificationResponse) -> Bool {
        guard IvyWeeklyReview.isReview(response.notification.request) else {
            return false
        }
        CurrentAppContext().frontmostViewController()?.ivyPresentWeeklyReview()
        return true
    }
}

// MARK: - Review

/// Overdue and upcoming tasks, the next seven days' events, and chats
/// waiting for an answer.
final class IvyWeeklyReviewViewController: UITableViewController {

    static var title: String {
        IvyLocalizedString("WEEKLY_REVIEW_TITLE", comment: "Title of the weekly review of tasks, events and chats.")
    }

    private enum Row {
        case task(IvyTask)
        case event(IvyCalendarItem)
        case waiting(IvyWaitingQuestion, chatName: String)
        case note(String)
    }

    private struct Section {
        let title: String
        let rows: [Row]
    }

    private static let maxRows = 10

    private var sections = [Section]()

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.dismiss(animated: true) }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        for name in [IvyTaskManager.tasksDidChange, IvyEventManager.eventsDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(reload), name: name, object: nil)
        }
        reload()
    }

    @objc
    private func reload() {
        let contents = IvyWeeklyReview.contents(
            tasks: IvyTaskManager.shared.allTasks(),
            events: IvyEventManager.shared.allEvents(),
            now: Date(),
        )
        let waiting: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            var excluded = IvySnoozedChats.shared.threadIds(tx: tx)
            if !IvyHiddenChats.shared.isRevealed {
                excluded.formUnion(IvyHiddenChats.shared.threadIds(tx: tx))
            }
            return IvyWaitingOnYou.find(excludedThreadIds: excluded, limit: Self.maxRows, tx: tx).map { question in
                .waiting(question, chatName: IvyFind.chatName(threadUniqueId: question.threadUniqueId, tx: tx))
            }
        }

        func section(_ title: String, _ rows: [Row], empty: String) -> Section {
            Section(title: title, rows: rows.isEmpty ? [.note(empty)] : Array(rows.prefix(Self.maxRows)))
        }
        var sections = [Section]()
        if !contents.overdueTasks.isEmpty {
            sections.append(section(
                IvyLocalizedString("WEEKLY_REVIEW_OVERDUE", comment: "Weekly review section with overdue tasks."),
                contents.overdueTasks.map(Row.task),
                empty: "",
            ))
        }
        sections.append(section(
            IvyLocalizedString("WEEKLY_REVIEW_DUE", comment: "Weekly review section with tasks due in the next seven days."),
            contents.dueTasks.map(Row.task),
            empty: IvyLocalizedString("WEEKLY_REVIEW_NO_TASKS", comment: "Shown in the weekly review when no tasks are due."),
        ))
        sections.append(section(
            IvyLocalizedString("WEEKLY_REVIEW_EVENTS", comment: "Weekly review section with the next seven days' events."),
            contents.events.map(Row.event),
            empty: IvyLocalizedString("WEEKLY_REVIEW_NO_EVENTS", comment: "Shown in the weekly review when no events are coming up."),
        ))
        sections.append(section(
            IvyHomeViewController.waitingTitle,
            waiting,
            empty: IvyLocalizedString("WEEKLY_REVIEW_NO_WAITING", comment: "Shown in the weekly review when no chat waits for an answer."),
        ))
        if !contents.somedayTasks.isEmpty {
            sections.append(section(
                IvyLocalizedString("WEEKLY_REVIEW_SOMEDAY", comment: "Weekly review section with tasks that have no due date."),
                contents.somedayTasks.map(Row.task),
                empty: "",
            ))
        }
        self.sections = sections
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        content.imageProperties.tintColor = .Signal.accent
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        switch sections[indexPath.section].rows[indexPath.row] {
        case .task(let task):
            content.text = task.title
            content.secondaryText = IvyTaskUI.subtitle(for: task, listName: nil)
            content.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
            if task.isOverdue(at: Date()) {
                content.secondaryTextProperties.color = .Signal.red
            }
        case .event(let item):
            content.text = {
                if case .event(let event) = item.kind { return event.title }
                return ""
            }()
            content.secondaryText = DateFormatter.localizedString(from: item.start, dateStyle: .medium, timeStyle: item.isAllDay ? .none : .short)
            content.image = UIImage(systemName: "calendar")
        case .waiting(let question, let chatName):
            content.text = chatName
            content.secondaryText = question.text
            content.secondaryTextProperties.numberOfLines = 2
            content.image = UIImage(systemName: "questionmark.bubble")
        case .note(let text):
            content = UIListContentConfiguration.cell()
            content.text = text
            content.textProperties.color = .Signal.secondaryLabel
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .task(let task):
            ivyPresentTaskEditor(task, isNew: false)
        case .event(let item):
            if case .event(let event) = item.kind {
                ivyPresentEventEditor(event, isNew: false)
            }
        case .waiting(let question, _):
            IvyFind.showMessage(threadUniqueId: question.threadUniqueId, messageUniqueId: question.messageUniqueId, from: self)
        case .note:
            break
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .task(let task) = sections[indexPath.section].rows[indexPath.row] else {
            return nil
        }
        let start = task.dueAt ?? Date()
        return IvyCalendarUI.swipeActions(for: IvyCalendarItem(kind: .task(task), start: start, end: start, isAllDay: task.isAllDay))
    }
}

// MARK: - Settings

/// When the weekly review is offered.
final class IvyWeeklyReviewSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyWeeklyReviewViewController.title
        updateTableContents()
    }

    private func setTime(_ time: IvyWeeklyReview.Time?) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in IvyWeeklyReview.setTime(time, tx: tx) }
        IvyWeeklyReview.reschedule()
    }

    private func updateTableContents() {
        let time = SSKEnvironment.shared.databaseStorageRef.read { tx in IvyWeeklyReview.time(tx: tx) }
        let contents = OWSTableContents(title: title)

        let section = OWSTableSection()
        section.footerTitle = IvyLocalizedString("WEEKLY_REVIEW_FOOTER", comment: "Explains the weekly review setting.")
        section.add(.switch(
            withText: IvyLocalizedString("WEEKLY_REVIEW_REMIND", comment: "Switch that turns on the weekly notification offering the review."),
            isOn: { time != nil },
            actionBlock: { [weak self] uiSwitch in
                self?.setTime(uiSwitch.isOn ? .suggested : nil)
                self?.updateTableContents()
            },
        ))
        if let time {
            let symbols = Calendar.current.weekdaySymbols
            section.add(.disclosureItem(
                withText: IvyLocalizedString("WEEKLY_REVIEW_DAY", comment: "Label of the day the weekly review is offered."),
                accessoryText: symbols[time.weekday - 1],
            ) { [weak self] in
                self?.chooseWeekday(current: time)
            })
            section.add(IvyFocusUI.timePickerItem(
                title: IvyLocalizedString("WEEKLY_REVIEW_TIME", comment: "Label of the time the weekly review is offered."),
                minutes: time.minutes,
            ) { [weak self] minutes in
                self?.setTime(IvyWeeklyReview.Time(weekday: time.weekday, minutes: minutes))
            })
        }
        contents.add(section)

        let openSection = OWSTableSection()
        openSection.add(.actionItem(
            withText: IvyLocalizedString("WEEKLY_REVIEW_OPEN", comment: "Button that opens the weekly review now."),
            textColor: .Signal.accent,
        ) { [weak self] in
            self?.ivyPresentWeeklyReview()
        })
        contents.add(openSection)
        self.contents = contents
    }

    private func chooseWeekday(current: IvyWeeklyReview.Time) {
        let sheet = ActionSheetController(title: IvyLocalizedString("WEEKLY_REVIEW_DAY", comment: "Label of the day the weekly review is offered."))
        let symbols = Calendar.current.weekdaySymbols
        for weekday in IvyFocusUI.orderedWeekdays {
            sheet.addAction(ActionSheetAction(title: symbols[weekday - 1]) { [weak self] _ in
                self?.setTime(IvyWeeklyReview.Time(weekday: weekday, minutes: current.minutes))
                self?.updateTableContents()
            })
        }
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }
}
