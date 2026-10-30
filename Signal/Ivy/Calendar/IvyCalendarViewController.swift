//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers

/// Events, tasks with a due date and open reminders: as an agenda under the
/// week, as a day's timeline, or as a month. Items take Ivy's pastel tones:
/// events blue, reminders brown, tasks green, overdue tasks red.
final class IvyCalendarViewController: UIViewController, HomeTabViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {

    enum Mode: Int, CaseIterable {
        case agenda
        case day
        case week
        case month

        var title: String {
            switch self {
            case .agenda: return IvyLocalizedString("CALENDAR_MODE_AGENDA", comment: "Calendar view: list of upcoming days.")
            case .day: return IvyLocalizedString("CALENDAR_MODE_DAY", comment: "Calendar view: one day.")
            case .week: return IvyLocalizedString("CALENDAR_MODE_WEEK", comment: "Calendar view: one week.")
            case .month: return IvyLocalizedString("CALENDAR_MODE_MONTH", comment: "Calendar view: one month.")
            }
        }
    }

    /// The views offered; a week is better seen in the week row and agenda.
    static let shownModes: [Mode] = [.agenda, .day, .month]

    /// Days the agenda shows ahead.
    static let agendaDays = 90

    private(set) var mode: Mode = .agenda
    /// The day the day, week and month views are about.
    private(set) var selectedDay = Calendar.current.startOfDay(for: Date())

    private let modeControl = UISegmentedControl()
    private let headerLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let navigationRow = UIStackView()
    private let monthView = IvyMonthView()
    private let monthCard = UIView()
    private let weekStrip = IvyWeekStrip()
    private let timeline = IvyDayTimelineView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    /// The table's sections: a heading, a date beside it, and the items.
    private(set) var sections: [(title: String, detail: String?, day: Date?, items: [IvyCalendarItem])] = []
    private var chatNames = [IvyChatReference: String]()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyCalendarUI.calendarTitle
        view.backgroundColor = .Signal.groupedBackground
        // Done only when shown as a sheet, not as a tab.
        if navigationController?.viewControllers.first === self, navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        navigationItem.rightBarButtonItems = [addButton(), moreButton(), todayBarButton()]

        for (index, mode) in Self.shownModes.enumerated() {
            modeControl.insertSegment(withTitle: mode.title, at: index, animated: false)
        }
        modeControl.selectedSegmentIndex = Self.shownModes.firstIndex(of: mode) ?? 0
        modeControl.addAction(UIAction { [weak self] _ in
            guard let self, Self.shownModes.indices.contains(modeControl.selectedSegmentIndex) else { return }
            setMode(Self.shownModes[modeControl.selectedSegmentIndex])
        }, for: .valueChanged)

        headerLabel.font = .dynamicTypeHeadline
        headerLabel.textColor = .Signal.label
        headerLabel.adjustsFontForContentSizeCategory = true
        configureArrow(previousButton, systemName: "chevron.backward", step: -1)
        configureArrow(nextButton, systemName: "chevron.forward", step: 1)
        previousButton.accessibilityLabel = IvyLocalizedString("CALENDAR_PREVIOUS", comment: "Button that shows the previous day, week or month.")
        nextButton.accessibilityLabel = IvyLocalizedString("CALENDAR_NEXT", comment: "Button that shows the next day, week or month.")
        headerLabel.textAlignment = .center
        navigationRow.addArrangedSubviews([previousButton, headerLabel, nextButton])
        navigationRow.axis = .horizontal
        navigationRow.alignment = .center
        navigationRow.spacing = 8

        monthView.onSelectDay = { [weak self] day in
            self?.select(day: day)
        }
        monthCard.backgroundColor = .Signal.secondaryGroupedBackground
        monthCard.layer.cornerRadius = 22
        monthCard.layer.cornerCurve = .continuous
        monthCard.addSubview(monthView)
        monthView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 12, left: 8, bottom: 10, right: 8))
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeMonth(_:)))
            swipe.direction = direction
            monthCard.addGestureRecognizer(swipe)
        }

        weekStrip.onSelectDay = { [weak self] day in
            self?.selectInWeek(day)
        }
        weekStrip.onMoveWeek = { [weak self] step in
            guard let self, let day = Calendar.current.date(byAdding: .weekOfYear, value: step, to: selectedDay) else { return }
            selectInWeek(day)
        }
        timeline.onOpen = { [weak self] item in
            self?.open(item)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(IvyAgendaCell.self, forCellReuseIdentifier: IvyAgendaCell.reuseIdentifier)
        tableView.register(IvySectionHeaderView.self, forHeaderFooterViewReuseIdentifier: IvySectionHeaderView.reuseIdentifier)
        tableView.sectionHeaderTopPadding = 0
        tableView.backgroundColor = .clear
        // The cards line up with the controls above them instead of
        // getting the list's own margin on top of the page's.
        tableView.directionalLayoutMargins = .zero
        tableView.preservesSuperviewLayoutMargins = false
        tableView.insetsLayoutMarginsFromSafeArea = false

        let stack = UIStackView(arrangedSubviews: [modeControl, navigationRow, weekStrip, monthCard, tableView, timeline])
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16)
        stack.setCustomSpacing(4, after: monthCard)
        stack.setCustomSpacing(4, after: weekStrip)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        for name in [IvyEventManager.eventsDidChange, IvyTaskManager.tasksDidChange, IvyReminderManager.remindersDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(reload), name: name, object: nil)
        }
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ivyUpdateProfileButton()
    }

    private func configureArrow(_ button: UIButton, systemName: String, step: Int) {
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in
            self?.move(by: step)
        }, for: .primaryActionTriggered)
    }

    // MARK: - Navigation

    func setMode(_ mode: Mode) {
        self.mode = mode
        modeControl.selectedSegmentIndex = Self.shownModes.firstIndex(of: mode) ?? UISegmentedControl.noSegment
        reload()
    }

    /// A day in the week row: the agenda scrolls to it, the day view shows
    /// it. Days before today open in the day view.
    private func selectInWeek(_ day: Date) {
        let calendar = Calendar.current
        selectedDay = calendar.startOfDay(for: day)
        if mode == .agenda, selectedDay < calendar.startOfDay(for: Date()) {
            setMode(.day)
            return
        }
        reload()
        if mode == .agenda {
            scrollAgenda(to: selectedDay)
        }
    }

    private func scrollAgenda(to day: Date) {
        guard let index = sections.firstIndex(where: { ($0.day ?? .distantPast) >= day && !$0.items.isEmpty }) else {
            return
        }
        tableView.scrollToRow(at: IndexPath(row: 0, section: index), at: .top, animated: true)
    }

    @objc
    private func didSwipeMonth(_ swipe: UISwipeGestureRecognizer) {
        move(by: swipe.direction == .left ? 1 : -1)
    }

    func select(day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        reload()
    }

    private func move(by step: Int) {
        let component: Calendar.Component
        switch mode {
        case .agenda, .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        if let day = Calendar.current.date(byAdding: component, value: step, to: selectedDay) {
            select(day: day)
        }
    }

    // MARK: - Contents

    /// The dates the current view shows.
    func visibleInterval(calendar: Calendar = .current) -> DateInterval {
        Self.visibleInterval(mode: mode, selectedDay: selectedDay, now: Date(), calendar: calendar)
    }

    static func visibleInterval(mode: Mode, selectedDay: Date, now: Date, calendar: Calendar) -> DateInterval {
        switch mode {
        case .agenda:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: agendaDays, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .day:
            return calendar.dateInterval(of: .day, for: selectedDay) ?? DateInterval(start: selectedDay, duration: 86_400)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: selectedDay) ?? DateInterval(start: selectedDay, duration: 7 * 86_400)
        case .month:
            let grid = IvyCalendar.monthGrid(containing: selectedDay, calendar: calendar)
            guard let first = grid.first, let last = grid.last, let end = calendar.date(byAdding: .day, value: 1, to: last) else {
                return DateInterval(start: selectedDay, duration: 31 * 86_400)
            }
            return DateInterval(start: first, end: end)
        }
    }

    @objc
    func reload() {
        let calendar = Calendar.current
        let interval = visibleInterval(calendar: calendar)
        let reminders = IvyReminderManager.shared.openReminders()
        let items = IvyCalendar.items(
            events: IvyEventManager.shared.allEvents(),
            tasks: IvyTaskManager.shared.allTasks(),
            reminders: reminders,
            in: interval,
            calendar: calendar,
        )
        chatNames = SSKEnvironment.shared.databaseStorageRef.read { tx in
            var names = [IvyChatReference: String]()
            for reminder in reminders {
                if let thread = reminder.chat.thread(tx: tx) {
                    names[reminder.chat] = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                }
            }
            return names
        }
        let byDay = IvyCalendar.itemsByDay(items, in: interval, calendar: calendar)

        switch mode {
        case .agenda:
            var sections: [(title: String, detail: String?, day: Date?, items: [IvyCalendarItem])] = []
            let overdue = IvyTaskManager.shared.allTasks().filter { $0.isOverdue(at: Date(), calendar: calendar) && !calendar.isDateInToday($0.dueAt ?? .distantPast) }
            if !overdue.isEmpty {
                sections.append((
                    title: IvyLocalizedString("TASKS_GROUP_OVERDUE", comment: "Header of the tasks whose due date has passed."),
                    detail: nil,
                    day: nil,
                    items: overdue.map { IvyCalendarItem(kind: .task($0), start: $0.dueAt ?? Date(), end: $0.dueAt ?? Date(), isAllDay: $0.isAllDay) },
                ))
            }
            sections += byDay.filter { !$0.items.isEmpty }.map { day in
                let heading = IvyCalendarUI.dayHeading(day.day, calendar: calendar)
                return (title: heading.title, detail: heading.detail, day: day.day, items: day.items)
            }
            self.sections = sections
        case .day:
            let heading = IvyCalendarUI.dayHeading(selectedDay, calendar: calendar)
            sections = [(title: heading.title, detail: heading.detail, day: selectedDay, items: byDay.first?.items ?? [])]
            timeline.update(day: selectedDay, items: byDay.first?.items ?? [], title: { [weak self] in self?.title(for: $0) ?? "" }, calendar: calendar)
        case .week:
            sections = byDay.map { day in
                let heading = IvyCalendarUI.dayHeading(day.day, calendar: calendar)
                return (title: heading.title, detail: heading.detail, day: day.day, items: day.items)
            }
        case .month:
            let dayItems = byDay.first { calendar.isDate($0.day, inSameDayAs: selectedDay) }?.items ?? []
            let heading = IvyCalendarUI.dayHeading(selectedDay, calendar: calendar)
            sections = [(title: heading.title, detail: heading.detail, day: selectedDay, items: dayItems)]
            monthView.update(
                month: selectedDay,
                selectedDay: selectedDay,
                tones: IvyCalendar.tonesByDay(items, in: interval, calendar: calendar),
                calendar: calendar,
            )
        }

        if mode == .agenda || mode == .day {
            weekStrip.update(selectedDay: selectedDay, tones: weekTones(reminders: reminders, calendar: calendar), calendar: calendar)
        }
        weekStrip.isHidden = mode == .month
        monthCard.isHidden = mode != .month
        navigationRow.isHidden = mode != .month
        timeline.isHidden = mode != .day
        tableView.isHidden = mode == .day
        headerLabel.text = headerText(interval: interval, calendar: calendar)
        navigationItem.title = navigationTitle(calendar: calendar)
        tableView.reloadData()
        tableView.backgroundView = mode != .day && sections.allSatisfy(\.items.isEmpty) ? emptyView() : nil
    }

    /// The dots for the week row.
    private func weekTones(reminders: [IvyReminder], calendar: Calendar) -> [Date: [IvyTone]] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else {
            return [:]
        }
        let items = IvyCalendar.items(
            events: IvyEventManager.shared.allEvents(),
            tasks: IvyTaskManager.shared.allTasks(),
            reminders: reminders,
            in: week,
            calendar: calendar,
        )
        return IvyCalendar.tonesByDay(items, in: week, calendar: calendar)
    }

    /// The month of the shown week or month, or the shown day.
    private func navigationTitle(calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        switch mode {
        case .day:
            formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        case .agenda, .week:
            formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(selectedDay, equalTo: Date(), toGranularity: .year) ? "MMMM" : "MMMMyyyy")
        }
        return formatter.string(from: selectedDay)
    }

    private func headerText(interval: DateInterval, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        switch mode {
        case .agenda:
            if calendar.isDateInToday(interval.start) {
                return IvyLocalizedString("CALENDAR_AGENDA_FROM_TODAY", comment: "Heading of the calendar's agenda, which lists everything coming up from today.")
            }
            formatter.setLocalizedDateFormatFromTemplate("MMMMd")
            return String(
                format: IvyLocalizedString("CALENDAR_AGENDA_FROM_DATE_FORMAT", comment: "Heading of the calendar's agenda when it starts on another day. Embeds {{ date }}."),
                formatter.string(from: interval.start),
            )
        case .day:
            formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
            return formatter.string(from: selectedDay)
        case .week:
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: interval.start) + " – " + formatter.string(from: interval.end.addingTimeInterval(-1))
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: selectedDay)
        }
    }

    /// Nothing planned: a card like Home's, with a way to add something.
    private func emptyView() -> UIView {
        let label = UILabel()
        label.text = IvyLocalizedString("CALENDAR_EMPTY", comment: "Shown in the calendar when nothing is planned for the shown dates.")
        label.font = .dynamicTypeBody
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0

        var configuration = UIButton.Configuration.plain()
        configuration.title = IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event.")
        configuration.image = UIImage(systemName: "plus.circle.fill")
        configuration.imagePadding = 8
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .Signal.accent
        let addButton = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.ivyPresentEventEditor(IvyLinkHandler.newEvent(), isNew: true)
        })
        addButton.contentHorizontalAlignment = .leading

        let content = UIStackView(arrangedSubviews: [label, addButton])
        content.axis = .vertical
        content.spacing = 14
        content.alignment = .fill
        let card = UIView()
        card.backgroundColor = .Signal.secondaryGroupedBackground
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.addSubview(content)
        content.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))

        let container = UIView()
        container.addSubview(card)
        card.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        card.autoPinEdge(toSuperviewEdge: .leading)
        card.autoPinEdge(toSuperviewEdge: .trailing)
        return container
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let item = sections[section]
        guard !item.items.isEmpty || mode == .month else {
            return nil
        }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: IvySectionHeaderView.reuseIdentifier) as? IvySectionHeaderView
        view?.configure(
            title: item.title,
            detail: item.detail,
            detailColor: item.day == nil ? IvyTone.red.strong : .Signal.secondaryLabel,
        )
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section].items.isEmpty && mode != .month ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: IvyAgendaCell.reuseIdentifier, for: indexPath)
        let item = sections[indexPath.section].items[indexPath.row]
        (cell as? IvyAgendaCell)?.configure(item: item, title: title(for: item), detail: detail(for: item))
        return cell
    }

    /// Where, or what kind of item and its list or chat.
    private func detail(for item: IvyCalendarItem) -> String? {
        switch item.kind {
        case .event(let event):
            var parts = [String]()
            if !event.location.isEmpty {
                parts.append(event.location)
            }
            if event.recurrence != nil {
                parts.append(IvyLocalizedString("CALENDAR_REPEATS", comment: "Shown under a calendar event that repeats."))
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .task(let task):
            let listName = task.listId.flatMap { id in IvyTaskManager.shared.lists().first { $0.id == id }?.name }
            return IvyTaskUI.subtitle(for: task, listName: listName)
        case .reminder:
            return IvyLocalizedString("REMINDER_KIND", comment: "Shown under a reminder in the calendar.")
        }
    }

    private func title(for item: IvyCalendarItem) -> String {
        switch item.kind {
        case .event(let event):
            return event.title
        case .task(let task):
            return task.title
        case .reminder(let reminder):
            return chatNames[reminder.chat] ?? IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(sections[indexPath.section].items[indexPath.row])
    }

    private func open(_ item: IvyCalendarItem) {
        switch item.kind {
        case .event(let event):
            ivyPresentEventEditor(event, isNew: false)
        case .task(let task):
            ivyPresentTaskEditor(task, isNew: false)
        case .reminder(let reminder):
            openReminder(reminder)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = sections[indexPath.section].items[indexPath.row]
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: IvyCalendarUI.menuActions(for: item))
        })
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        IvyCalendarUI.swipeActions(for: sections[indexPath.section].items[indexPath.row])
    }

    private func openReminder(_ reminder: IvyReminder) {
        let (threadId, messageId) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            (reminder.chat.thread(tx: tx)?.uniqueId, reminder.message?.message(tx: tx)?.uniqueId)
        }
        guard let threadId else {
            return
        }
        let root = view.window?.rootViewController ?? self
        root.dismiss(animated: true) {
            if let messageId {
                SignalApp.shared.presentConversationForThread(threadUniqueId: threadId, focusMessageId: messageId, animated: true)
            } else {
                SignalApp.shared.presentConversationAndScrollToFirstUnreadMessage(threadUniqueId: threadId, animated: true)
            }
        }
    }

    // MARK: - Buttons

    private func addButton() -> UIBarButtonItem {
        let newEvent = UIAction(
            title: IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event."),
            image: UIImage(systemName: "calendar.badge.plus"),
        ) { [weak self] _ in
            guard let self else { return }
            ivyPresentEventEditor(newEventDraft(), isNew: true)
        }
        let newTask = UIAction(
            title: IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task."),
            image: UIImage(systemName: "checklist"),
        ) { [weak self] _ in
            guard let self else { return }
            let dueAt = Calendar.current.date(bySettingHour: IvyTask.allDayReminderHour, minute: 0, second: 0, of: selectedDay)
            ivyPresentTaskEditor(IvyTask(title: "", dueAt: dueAt), isNew: true)
        }
        let planMessage = UIAction(
            title: IvyPlanMessageUI.planTitle,
            image: UIImage(systemName: "clock.badge"),
        ) { [weak self] _ in
            guard let self else { return }
            ivyPresentPlanMessage(chat: nil, sendAt: IvyPlanMessageUI.suggestedTime(on: selectedDay))
        }
        let proposePlan = UIAction(
            title: IvySharedPlansUI.proposeTitle,
            image: UIImage(systemName: "person.2"),
        ) { [weak self] _ in
            self?.ivyProposePlan(in: nil)
        }
        let item = UIBarButtonItem(title: nil, image: UIImage(systemName: "plus"), primaryAction: nil, menu: UIMenu(children: [newEvent, newTask, planMessage, proposePlan]))
        item.accessibilityLabel = IvyLocalizedString("EVENT_NEW", comment: "Action that makes a new calendar event.")
        return item
    }

    /// A one-hour event on the selected day, at the next full hour if that
    /// day is today.
    private func newEventDraft() -> IvyEvent {
        let calendar = Calendar.current
        let now = Date()
        var start: Date
        if calendar.isDate(selectedDay, inSameDayAs: now) {
            let nextHour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
            start = nextHour
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay) ?? selectedDay
        }
        start = max(start, selectedDay)
        return IvyEvent(title: "", startAt: start, endAt: start.addingTimeInterval(60 * 60))
    }

    private func todayBarButton() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            title: IvyLocalizedString("CALENDAR_TODAY", comment: "Button that goes back to today."),
            image: nil,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                selectInWeek(Date())
                if mode == .agenda {
                    tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
                }
            },
            menu: nil,
        )
        return item
    }

    private func moreButton() -> UIBarButtonItem {
        let importAction = UIAction(
            title: IvyLocalizedString("CALENDAR_IMPORT", comment: "Action that imports events from a calendar file."),
            image: UIImage(systemName: "square.and.arrow.down"),
        ) { [weak self] _ in
            self?.pickCalendarFile()
        }
        let exportAction = UIAction(
            title: IvyLocalizedString("CALENDAR_EXPORT", comment: "Action that saves all events as a calendar file."),
            image: UIImage(systemName: "square.and.arrow.up"),
        ) { [weak self] _ in
            guard let self else { return }
            let events = IvyEventManager.shared.allEvents()
            guard !events.isEmpty else {
                presentToast(text: IvyLocalizedString("CALENDAR_EXPORT_NOTHING", comment: "Shown when there are no events to export."))
                return
            }
            ivyExportCalendarFile(events, name: IvyCalendarUI.calendarTitle)
        }
        let item = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis.circle"), primaryAction: nil, menu: UIMenu(children: [importAction, exportAction]))
        item.accessibilityLabel = IvyLocalizedString("CALENDAR_MORE", comment: "Button that shows more calendar actions.")
        return item
    }

    // MARK: - Import

    private func pickCalendarFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [IvyCalendarUI.calendarContentType, .data], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        let text = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) }
        guard let text, let result = try? IvyEventManager.shared.importCalendar(text) else {
            OWSActionSheets.showErrorAlert(message: IvyLocalizedString("CALENDAR_IMPORT_FAILED", comment: "Shown when a file isn't a calendar file Ivy can read."))
            return
        }
        presentToast(text: String.localizedStringWithFormat(
            IvyLocalizedString("CALENDAR_IMPORTED_FORMAT", comment: "Shown after importing a calendar file. Embeds {{ number of new events }} and {{ number of updated events }}."),
            result.added,
            result.updated,
        ))
    }
}

// MARK: - Month

/// A month as a grid of days, with a dot in the tone of each kind of item.
final class IvyMonthView: UIView {

    var onSelectDay: ((Date) -> Void)?

    private let weekdayRow = UIStackView()
    private let grid = UIStackView()
    private(set) var dayButtons = [IvyDayButton]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        weekdayRow.axis = .horizontal
        weekdayRow.distribution = .fillEqually
        grid.axis = .vertical
        grid.distribution = .fillEqually
        grid.spacing = 2
        let stack = UIStackView(arrangedSubviews: [weekdayRow, grid])
        stack.axis = .vertical
        stack.spacing = 6
        addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(month: Date, selectedDay: Date, tones: [Date: [IvyTone]], calendar: Calendar) {
        weekdayRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        dayButtons = []

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        for index in 0..<7 {
            let label = UILabel()
            label.text = symbols[(index + calendar.firstWeekday - 1) % 7]
            label.font = UIFont.dynamicTypeCaption2Clamped.semibold()
            label.textColor = .Signal.secondaryLabel
            label.textAlignment = .center
            label.isAccessibilityElement = false
            weekdayRow.addArrangedSubview(label)
        }

        let days = IvyCalendar.monthGrid(containing: month, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        var row: UIStackView?
        for (index, day) in days.enumerated() {
            if index % 7 == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.distribution = .fillEqually
                grid.addArrangedSubview(newRow)
                row = newRow
            }
            let button = IvyDayButton(diameter: 34)
            button.configure(
                day: day,
                isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                isToday: calendar.isDate(day, inSameDayAs: today),
                isDimmed: !calendar.isDate(day, equalTo: month, toGranularity: .month),
                tones: tones[calendar.startOfDay(for: day)] ?? [],
                calendar: calendar,
            )
            button.onTap = { [weak self] in self?.onSelectDay?(day) }
            row?.addArrangedSubview(button)
            dayButtons.append(button)
        }
    }
}
