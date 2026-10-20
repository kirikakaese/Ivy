//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Shared plans: proposing times in a chat, answering, counting the
/// answers and confirming the agreed time (see `IvySharedPlans`).
@MainActor
enum IvySharedPlansUI {

    static var proposeTitle: String {
        IvyLocalizedString("PLAN_PROPOSE", comment: "Action that proposes an event with several times in a chat.")
    }

    // MARK: - Watching for agreed plans

    private static var trigger: IvyPlanScanTrigger?

    /// Called when the app is ready: agreed plans that arrive go into the
    /// calendar.
    static func start() {
        guard trigger == nil else {
            return
        }
        let trigger = IvyPlanScanTrigger()
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(trigger)
        NotificationCenter.default.addObserver(
            trigger,
            selector: #selector(IvyPlanScanTrigger.scanSoon),
            name: UIApplication.didBecomeActiveNotification,
            object: nil,
        )
        self.trigger = trigger
        trigger.scanSoon()
    }

    // MARK: - Text

    static func timeText(_ option: IvyPlan.Option) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = option.isAllDay ? .none : .short
        return formatter.string(from: option.start, to: option.isAllDay ? option.start : option.end)
    }

    static func proposalText(_ plan: IvyPlan) -> String {
        var lines = ["📅 " + plan.title]
        if !plan.location.isEmpty {
            lines.append("📍 " + plan.location)
        }
        lines.append(IvyLocalizedString("PLAN_PROPOSAL_QUESTION", comment: "In a proposed plan message: asks which of the times work."))
        for option in plan.options {
            lines.append("\(option.number). " + timeText(option))
        }
        lines.append(IvyLocalizedString("PLAN_PROPOSAL_HOW_TO_ANSWER", comment: "In a proposed plan message: explains how to answer."))
        return lines.joined(separator: "\n")
    }

    static func confirmedText(_ plan: IvyPlan) -> String {
        guard let option = plan.options.first else {
            return plan.title
        }
        return String(
            format: IvyLocalizedString("PLAN_CONFIRMED_FORMAT", comment: "Message that announces the agreed time of a plan. Embeds {{ title }} and {{ time }}."),
            plan.title,
            timeText(option),
        )
    }

    // MARK: - Sending

    /// Sends a plan as text with its calendar file, optionally as a reply.
    static func send(_ plan: IvyPlan, text: String, in thread: TSThread, replyingTo message: TSMessage? = nil) {
        let ics = IvySharedPlans.ics(for: plan)
        let quote = message.flatMap { message in
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(
                    originalMessage: message,
                    loadNormalizedImage: NormalizedImage.loadImage(imageSource:maxPixelSize:),
                    tx: tx,
                )
            }
        }
        Task {
            do {
                let dataSource = try DataSourcePath(writingTempFileData: Data(ics.utf8), fileExtension: IvyICS.fileExtension)
                dataSource.sourceFilename = fileName(for: plan)
                let previewable = try PreviewableAttachment.buildAttachment(
                    dataSource: dataSource,
                    dataUTI: IvyCalendarUI.calendarContentType.identifier,
                    attachmentLimits: OutgoingAttachmentLimits.currentLimits(),
                )
                let sendable = try await SendableAttachment.forPreviewableAttachment(previewable, imageQualityLevel: .one)
                ThreadUtil.enqueueMessage(
                    body: MessageBody(text: text, ranges: .empty),
                    attachments: ([sendable], isViewOnce: false),
                    thread: thread,
                    quotedReplyDraft: quote,
                )
            } catch {
                Logger.warn("Couldn't send a plan: \(error)")
                CurrentAppContext().frontmostViewController()?.presentToast(
                    text: IvyLocalizedString("PLAN_SEND_FAILED", comment: "Shown when a plan couldn't be sent."),
                )
            }
        }
    }

    private static func fileName(for plan: IvyPlan) -> String {
        let name = plan.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined()
            .trimmingCharacters(in: .whitespaces)
        return String((name.isEmpty ? IvyCalendarUI.calendarTitle : name).prefix(60)) + "." + IvyICS.fileExtension
    }

    /// Sends a short reply that picks one of the times.
    static func answer(_ plan: IvyPlan, option: IvyPlan.Option, to message: TSMessage, in thread: TSThread) {
        let quote = SSKEnvironment.shared.databaseStorageRef.read { tx in
            DependenciesBridge.shared.quotedReplyManager.buildDraftQuotedReply(
                originalMessage: message,
                loadNormalizedImage: NormalizedImage.loadImage(imageSource:maxPixelSize:),
                tx: tx,
            )
        }
        ThreadUtil.enqueueMessage(
            body: MessageBody(text: IvySharedPlans.answerText(number: option.number, detail: timeText(option)), ranges: .empty),
            thread: thread,
            quotedReplyDraft: quote,
        )
    }

    /// Announces the agreed time in the chat and puts it into the calendar.
    static func confirm(_ plan: IvyPlan, option: IvyPlan.Option, replyingTo message: TSMessage, in thread: TSThread) {
        guard let confirmed = plan.confirmed(option: option.number) else {
            return
        }
        _ = try? IvyEventManager.shared.importCalendar(IvySharedPlans.ics(for: confirmed))
        send(confirmed, text: confirmedText(confirmed), in: thread, replyingTo: message)
    }
}

/// Scans for agreed plans a moment after messages change.
@MainActor
final class IvyPlanScanTrigger: NSObject, DatabaseChangeDelegate {

    private var isScheduled = false

    @objc
    func scanSoon() {
        guard !isScheduled else {
            return
        }
        isScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.isScheduled = false
            IvyPlanWatcher.shared.scan()
        }
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdateInteractions {
            scanSoon()
        }
    }

    func databaseChangesDidUpdateExternally() {
        scanSoon()
    }

    func databaseChangesDidReset() {
        scanSoon()
    }
}

// MARK: - Proposing

extension UIViewController {

    /// Proposes times for an event in a chat. Without a chat, asks for one.
    func ivyProposePlan(in thread: TSThread?) {
        if let thread {
            presentFormSheet(OWSNavigationController(rootViewController: IvyPlanProposalViewController(thread: thread)), animated: true)
            return
        }
        let chooser = IvyChatChooserViewController(preferredChat: nil) { [weak self] thread in
            self?.ivyProposePlan(in: thread)
        }
        chooser.title = IvySharedPlansUI.proposeTitle
        presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
    }
}

/// A title, a place, how long, and a few times to choose from.
final class IvyPlanProposalViewController: UIViewController {

    private enum Duration: Int, CaseIterable {
        case halfHour, hour, twoHours, allDay

        var interval: TimeInterval {
            switch self {
            case .halfHour: return 30 * 60
            case .hour: return 60 * 60
            case .twoHours: return 2 * 60 * 60
            case .allDay: return 0
            }
        }

        var title: String {
            switch self {
            case .halfHour: return IvyLocalizedString("PLAN_DURATION_HALF_HOUR", comment: "Length of a proposed event: 30 minutes.")
            case .hour: return IvyLocalizedString("PLAN_DURATION_HOUR", comment: "Length of a proposed event: one hour.")
            case .twoHours: return IvyLocalizedString("PLAN_DURATION_TWO_HOURS", comment: "Length of a proposed event: two hours.")
            case .allDay: return IvyLocalizedString("PLAN_DURATION_ALL_DAY", comment: "Length of a proposed event: all day.")
            }
        }
    }

    private let thread: TSThread
    private let titleField = UITextField()
    private let locationField = UITextField()
    private let durationControl = UISegmentedControl()
    private let optionsStack = UIStackView()
    private let addButton = UIButton(type: .system)
    private var pickers = [UIDatePicker]()

    init(thread: TSThread) {
        self.thread = thread
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvySharedPlansUI.proposeTitle
        view.backgroundColor = .Signal.groupedBackground
        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: IvyLocalizedString("PLAN_SEND", comment: "Button that sends a proposed plan to the chat."),
            primaryAction: UIAction { [weak self] _ in self?.send() },
        )

        for (field, placeholder) in [
            (titleField, IvyLocalizedString("PLAN_TITLE_PLACEHOLDER", comment: "Placeholder of a proposed plan's title, for example Dinner.")),
            (locationField, IvyLocalizedString("PLAN_LOCATION_PLACEHOLDER", comment: "Placeholder of a proposed plan's place.")),
        ] {
            field.placeholder = placeholder
            field.borderStyle = .roundedRect
            field.font = .dynamicTypeBody
        }

        for duration in Duration.allCases {
            durationControl.insertSegment(withTitle: duration.title, at: duration.rawValue, animated: false)
        }
        durationControl.selectedSegmentIndex = Duration.hour.rawValue
        durationControl.addAction(UIAction { [weak self] _ in self?.durationChanged() }, for: .valueChanged)

        let timesLabel = UILabel()
        timesLabel.text = IvyLocalizedString("PLAN_TIMES", comment: "Header of the times to choose from in a proposed plan.")
        timesLabel.font = .dynamicTypeFootnote
        timesLabel.textColor = .Signal.secondaryLabel

        optionsStack.axis = .vertical
        optionsStack.spacing = 8

        var add = UIButton.Configuration.plain()
        add.title = IvyLocalizedString("PLAN_ADD_TIME", comment: "Button that adds another time to a proposed plan.")
        add.image = UIImage(systemName: "plus.circle")
        add.imagePadding = 6
        addButton.configuration = add
        addButton.contentHorizontalAlignment = .leading
        addButton.addAction(UIAction { [weak self] _ in self?.addOption() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [titleField, locationField, durationControl, timesLabel, optionsStack, addButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: durationControl)
        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
        ])

        // Two evenings to start with: tomorrow and the day after, at 18:00.
        let calendar = Calendar.current
        for days in 1...2 {
            let day = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
            addOption(at: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        titleField.becomeFirstResponder()
    }

    private var duration: Duration {
        Duration(rawValue: durationControl.selectedSegmentIndex) ?? .hour
    }

    private func durationChanged() {
        for picker in pickers {
            picker.datePickerMode = duration == .allDay ? .date : .dateAndTime
        }
    }

    private func addOption(at date: Date? = nil) {
        guard pickers.count < IvySharedPlans.maxOptions else {
            return
        }
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .compact
        picker.datePickerMode = duration == .allDay ? .date : .dateAndTime
        picker.minimumDate = Date()
        picker.date = date ?? (pickers.last?.date.addingTimeInterval(24 * 60 * 60) ?? Date())
        pickers.append(picker)

        let number = UILabel()
        number.font = .dynamicTypeHeadline
        number.textColor = .Signal.accent
        number.setContentHuggingPriority(.required, for: .horizontal)
        let remove = UIButton(type: .system, primaryAction: UIAction { [weak self, weak picker] _ in
            guard let self, let picker else { return }
            removeOption(picker)
        })
        remove.setImage(UIImage(systemName: "minus.circle"), for: .normal)
        remove.tintColor = .Signal.red
        let row = UIStackView(arrangedSubviews: [number, picker, UIView(), remove])
        row.spacing = 10
        row.alignment = .center
        optionsStack.addArrangedSubview(row)
        renumber()
    }

    private func removeOption(_ picker: UIDatePicker) {
        guard pickers.count > 1, let index = pickers.firstIndex(of: picker) else {
            return
        }
        pickers.remove(at: index)
        optionsStack.arrangedSubviews[index].removeFromSuperview()
        renumber()
    }

    private func renumber() {
        for (index, row) in optionsStack.arrangedSubviews.enumerated() {
            ((row as? UIStackView)?.arrangedSubviews.first as? UILabel)?.text = "\(index + 1)."
        }
        addButton.isHidden = pickers.count >= IvySharedPlans.maxOptions
    }

    private func send() {
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            presentToast(text: IvyLocalizedString("PLAN_NEEDS_TITLE", comment: "Shown when a proposed plan has no title."))
            return
        }
        let calendar = Calendar.current
        let options = pickers.enumerated().map { index, picker -> IvyPlan.Option in
            if duration == .allDay {
                let day = calendar.startOfDay(for: picker.date)
                return IvyPlan.Option(number: index + 1, start: day, end: day, isAllDay: true)
            }
            return IvyPlan.Option(number: index + 1, start: picker.date, end: picker.date.addingTimeInterval(duration.interval))
        }
        let plan = IvyPlan(
            title: title,
            location: (locationField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            options: options,
        )
        let thread = self.thread
        dismiss(animated: true) {
            IvySharedPlansUI.send(plan, text: IvySharedPlansUI.proposalText(plan), in: thread)
        }
    }
}

// MARK: - Answers

/// How many people picked each time. The person who proposed the plan can
/// confirm a time from here.
final class IvyPlanAnswersViewController: OWSTableViewController2 {

    private let plan: IvyPlan
    private let message: TSMessage
    private let thread: TSThread

    init(plan: IvyPlan, message: TSMessage, thread: TSThread) {
        self.plan = plan
        self.message = message
        self.thread = thread
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = plan.title
        navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        updateTableContents()
    }

    private func updateTableContents() {
        let you = IvyLocalizedString("PLAN_YOU", comment: "Stands for the user in the list of who picked a time.")
        let tally: [Int: [String]] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let answers = IvySharedPlans.answers(to: message, tx: tx) { reply in
                guard let incoming = reply as? TSIncomingMessage else {
                    return you
                }
                return SSKEnvironment.shared.contactManagerRef.displayName(for: incoming.authorAddress, tx: tx).resolvedValue()
            }
            return IvySharedPlans.tally(answers, plan: plan)
        }
        let isOrganizer = message is TSOutgoingMessage
        let contents = OWSTableContents(title: title)
        let section = OWSTableSection()
        section.footerTitle = isOrganizer
            ? IvyLocalizedString("PLAN_ANSWERS_FOOTER_ORGANIZER", comment: "Explains how to confirm a time of a proposed plan.")
            : IvyLocalizedString("PLAN_ANSWERS_FOOTER", comment: "Explains the list of answers to a proposed plan.")
        let best = tally.values.map(\.count).max() ?? 0
        for option in plan.options {
            let voters = tally[option.number] ?? []
            let subtitle = voters.isEmpty
                ? IvyLocalizedString("PLAN_NO_ANSWERS", comment: "Shown under a time of a proposed plan nobody picked yet.")
                : voters.joined(separator: ", ")
            let title = "\(option.number). " + IvySharedPlansUI.timeText(option) + "  ·  " + voters.count.formatted()
            if isOrganizer {
                section.add(.disclosureItem(
                    withText: title,
                    subtitle: subtitle,
                    textColor: voters.count == best && best > 0 ? .Signal.accent : nil,
                ) { [weak self] in
                    self?.confirmPrompt(option)
                })
            } else {
                let isLeading = voters.count == best && best > 0
                section.add(OWSTableItem(customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    var content = UIListContentConfiguration.subtitleCell()
                    content.text = title
                    content.textProperties.color = isLeading ? .Signal.accent : .Signal.label
                    content.secondaryText = subtitle
                    content.secondaryTextProperties.color = .Signal.secondaryLabel
                    cell.contentConfiguration = content
                    cell.selectionStyle = .none
                    return cell
                }))
            }
        }
        contents.add(section)
        self.contents = contents
    }

    private func confirmPrompt(_ option: IvyPlan.Option) {
        let sheet = ActionSheetController(
            title: IvyLocalizedString("PLAN_CONFIRM_TITLE", comment: "Title of the confirmation before agreeing on a time of a plan."),
            message: IvySharedPlansUI.timeText(option),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("PLAN_CONFIRM", comment: "Button that agrees on a time of a plan and tells the chat."),
        ) { [weak self] _ in
            guard let self else { return }
            IvySharedPlansUI.confirm(plan, option: option, replyingTo: message, in: thread)
            dismiss(animated: true)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }
}

// MARK: - Conversation

extension ConversationViewController {

    /// "Answer Plan" and "Plan Answers" on a message with a proposed plan.
    func ivyPlanContextMenuActions(interaction: TSInteraction, thread: TSThread) -> [ContextMenuAction] {
        guard
            let message = interaction as? TSMessage,
            let plan = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in IvySharedPlans.plan(in: message, tx: tx) }),
            !plan.isConfirmed
        else {
            return []
        }
        var actions = [ContextMenuAction]()
        if message is TSIncomingMessage {
            actions.append(ContextMenuAction(
                title: IvyLocalizedString("PLAN_ANSWER", comment: "Action that picks a time of a proposed plan."),
                image: UIImage(systemName: "hand.raised"),
            ) { [weak self] _ in
                self?.ivyAnswerPlan(plan, message: message, thread: thread)
            })
        }
        actions.append(ContextMenuAction(
            title: IvyLocalizedString("PLAN_ANSWERS", comment: "Action that shows who picked which time of a proposed plan."),
            image: UIImage(systemName: "chart.bar"),
        ) { [weak self] _ in
            let answers = IvyPlanAnswersViewController(plan: plan, message: message, thread: thread)
            self?.presentFormSheet(OWSNavigationController(rootViewController: answers), animated: true)
        })
        return actions
    }

    private func ivyAnswerPlan(_ plan: IvyPlan, message: TSMessage, thread: TSThread) {
        let sheet = ActionSheetController(title: plan.title, message: IvyLocalizedString("PLAN_PROPOSAL_QUESTION", comment: "In a proposed plan message: asks which of the times work."))
        for option in plan.options {
            sheet.addAction(ActionSheetAction(title: "\(option.number). " + IvySharedPlansUI.timeText(option)) { _ in
                IvySharedPlansUI.answer(plan, option: option, to: message, in: thread)
            })
        }
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }
}

extension ConversationSettingsViewController {

    /// "Propose a Plan" in the chat's settings.
    func ivyAddProposePlanItem(to section: OWSTableSection) {
        section.add(.disclosureItem(
            icon: .contextMenuMessage,
            withText: IvySharedPlansUI.proposeTitle,
            actionBlock: { [weak self] in
                guard let self else { return }
                ivyProposePlan(in: thread)
            },
        ))
    }
}
