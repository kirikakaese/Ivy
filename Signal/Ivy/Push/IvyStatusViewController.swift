//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

/// Ivy Status inside Ivy: how the services are doing, open incidents and
/// maintenance, 90 days per service and the measurements. When the relay
/// doesn't answer, the last report that arrived is shown as such.
final class IvyStatusViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    /// How often the screen asks again while it's open.
    static let refreshInterval: TimeInterval = 60

    private enum Problem {
        /// The device is online, but the relay doesn't answer.
        case unreachable
        case offline
    }

    private enum Row {
        case post(IvyStatusReport.Post)
        case service(IvyStatusReport.Component)
        case metrics(IvyStatusReport.Metrics)
    }

    private struct Section {
        let title: String?
        var detail: String?
        let rows: [Row]
    }

    private let relayURL: URL
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let hero = IvyStatusHeroView()
    private var report: IvyStatusReport?
    private var received: Date?
    private var isLive = false
    private var problem: Problem?
    private var sections = [Section]()
    private var expanded = Set<String>()
    private var selectedDays = [String: Int]()
    private var timer: Timer?

    init(relayURL: URL) {
        self.relayURL = relayURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// For the banner and Settings: the status screen in a sheet.
    static func present(from viewController: UIViewController) {
        guard let relayURL = IvyPushRelay.shared.connection?.relayURL ?? IvyPushRelay.builtInRelayURL else {
            return
        }
        viewController.presentFormSheet(OWSNavigationController(rootViewController: IvyStatusViewController(relayURL: relayURL)), animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("SERVICE_STATUS_OPEN_BUTTON", comment: "Button on the chat list banner that opens the Ivy Status page.")
        view.backgroundColor = .Signal.groupedBackground
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        let browser = UIBarButtonItem(image: UIImage(systemName: "safari"), primaryAction: UIAction { [weak self] _ in self?.openInBrowser() })
        browser.accessibilityLabel = Self.openInBrowserTitle
        navigationItem.rightBarButtonItem = browser

        hero.onRetry = { [weak self] in self?.refresh() }
        hero.onOpenInBrowser = { [weak self] in self?.openInBrowser() }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(IvyStatusPostCell.self, forCellReuseIdentifier: IvyStatusPostCell.reuseIdentifier)
        tableView.register(IvyStatusServiceCell.self, forCellReuseIdentifier: IvyStatusServiceCell.reuseIdentifier)
        tableView.register(IvyStatusMetricsCell.self, forCellReuseIdentifier: IvyStatusMetricsCell.reuseIdentifier)
        tableView.register(IvySectionHeaderView.self, forHeaderFooterViewReuseIdentifier: IvySectionHeaderView.reuseIdentifier)
        tableView.sectionHeaderTopPadding = 0
        tableView.backgroundColor = .clear
        tableView.tableHeaderView = hero
        let refreshControl = UIRefreshControl()
        refreshControl.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        if let saved = IvyStatusReport.Saved.load() {
            report = saved.report
            received = saved.received
        }
        render()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        let height = hero.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        ).height
        if hero.frame.size != CGSize(width: width, height: height) {
            hero.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = hero
        }
    }

    // MARK: - Loading

    private func refresh() {
        let relayURL = relayURL
        Task { @MainActor [weak self] in
            do {
                let report = try await IvyStatusReport.fetch(relayURL: relayURL)
                guard let self else { return }
                self.report = report
                received = Date()
                isLive = true
                problem = nil
            } catch {
                guard let self else { return }
                isLive = false
                problem = SSKEnvironment.shared.reachabilityManagerRef.isReachable ? .unreachable : .offline
            }
            self?.tableView.refreshControl?.endRefreshing()
            self?.render()
        }
    }

    private func render() {
        hero.update(state: heroState())
        var sections = [Section]()
        if let report {
            if isLive {
                let posts = report.active ?? []
                if !posts.isEmpty {
                    sections.append(Section(title: nil, rows: posts.map { .post($0) }))
                }
                if let upcoming = report.upcoming, !upcoming.isEmpty {
                    sections.append(Section(title: IvyLocalizedString("STATUS_PAGE_UPCOMING", comment: "Heading of planned maintenance on the status screen."), rows: upcoming.map { .post($0) }))
                }
                sections.append(Section(title: IvyLocalizedString("STATUS_PAGE_SERVICES", comment: "Heading of the services on the status screen."), rows: report.components.map { .service($0) }))
                if let metrics = report.metrics {
                    sections.append(Section(title: IvyLocalizedString("STATUS_PAGE_MEASUREMENTS", comment: "Heading of the measurements on the status screen."), rows: [.metrics(metrics)]))
                }
                if let recent = report.recent, !recent.isEmpty {
                    sections.append(Section(title: IvyLocalizedString("STATUS_PAGE_RECENT", comment: "Heading of the posts of the past 14 days on the status screen."), rows: recent.map { .post($0) }))
                }
            } else {
                sections.append(Section(
                    title: IvyLocalizedString("STATUS_PAGE_LAST_KNOWN", comment: "Heading of the last status that arrived, shown when Ivy Status can't be reached."),
                    detail: received.map { DateUtil.formatDynamicDateShort($0).formatted },
                    rows: report.components.map { .service($0) },
                ))
            }
        }
        self.sections = sections
        tableView.tableFooterView = problem == nil ? nil : footer()
        tableView.reloadData()
        view.setNeedsLayout()
    }

    private func heroState() -> IvyStatusHeroView.State {
        switch problem {
        case .unreachable:
            return .init(
                tone: .brown,
                title: IvyLocalizedString("STATUS_PAGE_UNREACHABLE_TITLE", comment: "Heading on the status screen when Ivy Status can't be reached."),
                detail: IvyLocalizedString("STATUS_PAGE_UNREACHABLE_DETAIL", comment: "Text on the status screen when Ivy Status can't be reached."),
                showsRetry: true,
                showsBrowser: true,
            )
        case .offline:
            return .init(
                tone: nil,
                title: IvyLocalizedString("STATUS_PAGE_OFFLINE_TITLE", comment: "Heading on the status screen when the device is offline."),
                detail: IvyLocalizedString("STATUS_PAGE_OFFLINE_DETAIL", comment: "Text on the status screen when the device is offline."),
                showsRetry: true,
                showsBrowser: false,
            )
        case nil:
            break
        }
        guard isLive, let report else {
            return .init(tone: nil, title: IvyLocalizedString("STATUS_PAGE_CHECKING", comment: "Heading on the status screen while it loads."), detail: nil, showsRetry: false, showsBrowser: false)
        }
        var detail = IvyStatusTexts.statusDetail(report.status)
        if let checked = report.checked {
            let relative = RelativeDateTimeFormatter().localizedString(for: checked, relativeTo: Date())
            detail += " " + String(format: IvyLocalizedString("STATUS_PAGE_CHECKED_FORMAT", comment: "When Ivy Status last checked, on the status screen. Embeds {{ a relative time like 1 min ago }}."), relative)
        }
        return .init(tone: IvyStatusTexts.tone(for: report.status), title: IvyStatusTexts.statusTitle(report.status), detail: detail, showsRetry: false, showsBrowser: false)
    }

    private func footer() -> UIView {
        let label = UILabel()
        label.text = IvyLocalizedString("STATUS_PAGE_RETRYING", comment: "Footer of the status screen when it can't load: it tries again by itself.")
        label.font = .dynamicTypeFootnote
        label.textColor = .Signal.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 56)
        return label
    }

    private func openInBrowser() {
        present(SFSafariViewController(url: IvyPushRelay.statusPageURL(for: relayURL)), animated: true)
    }

    static var openInBrowserTitle: String {
        IvyLocalizedString("STATUS_PAGE_OPEN_IN_BROWSER", comment: "Button that opens Ivy Status in the browser.")
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = sections[section].title else {
            return nil
        }
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: IvySectionHeaderView.reuseIdentifier) as? IvySectionHeaderView
        view?.configure(title: title, detail: sections[section].detail)
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section].title == nil ? 12 : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch sections[indexPath.section].rows[indexPath.row] {
        case .post(let post):
            let cell = tableView.dequeueReusableCell(withIdentifier: IvyStatusPostCell.reuseIdentifier, for: indexPath)
            (cell as? IvyStatusPostCell)?.configure(post: post, report: report)
            return cell
        case .service(let component):
            let cell = tableView.dequeueReusableCell(withIdentifier: IvyStatusServiceCell.reuseIdentifier, for: indexPath)
            (cell as? IvyStatusServiceCell)?.configure(
                component: component,
                isExpanded: isLive && expanded.contains(component.id),
                isStale: !isLive,
                selectedDay: selectedDays[component.id],
            ) { [weak self] index in
                self?.selectedDays[component.id] = index
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            return cell
        case .metrics(let metrics):
            let cell = tableView.dequeueReusableCell(withIdentifier: IvyStatusMetricsCell.reuseIdentifier, for: indexPath)
            (cell as? IvyStatusMetricsCell)?.configure(metrics)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard isLive, case .service = sections[indexPath.section].rows[indexPath.row] else {
            return nil
        }
        return indexPath
    }

    /// Tapping a service folds its 90 days out or away.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case .service(let component) = sections[indexPath.section].rows[indexPath.row] else {
            return
        }
        if expanded.contains(component.id) {
            expanded.remove(component.id)
        } else {
            expanded.insert(component.id)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}

// MARK: - Texts

/// Ivy Status's words in Ivy's languages. Services are named by their ID;
/// unknown ones keep the name the server sends.
enum IvyStatusTexts {

    static func tone(for status: String) -> IvyTone? {
        switch status {
        case "ok": return .green
        case "maintenance": return .blue
        case "degraded": return .brown
        case "down": return .red
        default: return nil
        }
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case "ok": return IvyLocalizedString("STATUS_PAGE_OK_TITLE", comment: "Heading on the status screen when everything works.")
        case "maintenance": return IvyLocalizedString("SERVICE_STATUS_MAINTENANCE_TITLE", comment: "Chat list banner title during maintenance of Ivy's services.")
        case "degraded": return IvyLocalizedString("STATUS_PAGE_DEGRADED_TITLE", comment: "Heading on the status screen when some parts have trouble.")
        case "down": return IvyLocalizedString("STATUS_PAGE_DOWN_TITLE", comment: "Heading on the status screen when part of Ivy isn't working.")
        default: return IvyLocalizedString("STATUS_PAGE_CHECKING", comment: "Heading on the status screen while it loads.")
        }
    }

    static func statusDetail(_ status: String) -> String {
        switch status {
        case "ok": return IvyLocalizedString("STATUS_PAGE_OK_DETAIL", comment: "Text on the status screen when everything works.")
        case "maintenance", "degraded": return IvyLocalizedString("SERVICE_STATUS_DEGRADED_DETAIL", comment: "Chat list banner text when notifications may be late.")
        case "down": return IvyLocalizedString("SERVICE_STATUS_DOWN_DETAIL", comment: "Chat list banner text when instant notifications may not work.")
        default: return ""
        }
    }

    static func chip(_ status: String) -> String {
        switch status {
        case "ok": return IvyLocalizedString("STATUS_PAGE_CHIP_OK", comment: "A service's state on the status screen: working.")
        case "maintenance": return IvyLocalizedString("STATUS_PAGE_CHIP_MAINTENANCE", comment: "A service's state on the status screen: under maintenance.")
        case "degraded": return IvyLocalizedString("STATUS_PAGE_CHIP_DEGRADED", comment: "A service's state on the status screen: some trouble.")
        case "down": return IvyLocalizedString("STATUS_PAGE_CHIP_DOWN", comment: "A service's state on the status screen: down.")
        default: return IvyLocalizedString("STATUS_PAGE_CHIP_UNKNOWN", comment: "A service's state on the status screen: unknown.")
        }
    }

    static func name(id: String, fallback: String) -> String {
        switch id {
        case "relay": return IvyLocalizedString("STATUS_SERVICE_RELAY", comment: "Name of the push relay on the status screen.")
        case "apple": return IvyLocalizedString("STATUS_SERVICE_APPLE", comment: "Name of Apple's push delivery on the status screen.")
        case "signal": return IvyLocalizedString("STATUS_SERVICE_SIGNAL", comment: "Name of Signal's service on the status screen.")
        default: return fallback
        }
    }

    static func description(id: String, fallback: String) -> String {
        switch id {
        case "relay": return IvyLocalizedString("STATUS_SERVICE_RELAY_DETAIL", comment: "What the push relay does, on the status screen.")
        case "apple": return IvyLocalizedString("STATUS_SERVICE_APPLE_DETAIL", comment: "What Apple's push delivery does, on the status screen.")
        case "signal": return IvyLocalizedString("STATUS_SERVICE_SIGNAL_DETAIL", comment: "What is checked of Signal's service, on the status screen.")
        default: return fallback
        }
    }

    /// The server's names of the services, in Ivy's words, for posts.
    static func names(_ names: [String], report: IvyStatusReport?) -> [String] {
        names.map { name in
            guard let component = report?.components.first(where: { $0.name == name }) else { return name }
            return Self.name(id: component.id, fallback: name)
        }
    }

    static func kind(_ kind: String) -> String {
        switch kind {
        case "incident": return IvyLocalizedString("STATUS_PAGE_KIND_INCIDENT", comment: "Kind of post on the status screen: an incident.")
        case "maintenance": return IvyLocalizedString("SERVICE_STATUS_MAINTENANCE_TITLE", comment: "Chat list banner title during maintenance of Ivy's services.")
        default: return IvyLocalizedString("SERVICE_STATUS_NOTICE_TITLE", comment: "Chat list banner title for a notice from Ivy Status.")
        }
    }

    static func step(_ step: String) -> String {
        switch step {
        case "investigating": return IvyLocalizedString("STATUS_STEP_INVESTIGATING", comment: "Step of an incident on the status screen.")
        case "identified": return IvyLocalizedString("STATUS_STEP_IDENTIFIED", comment: "Step of an incident on the status screen.")
        case "monitoring": return IvyLocalizedString("STATUS_STEP_MONITORING", comment: "Step of an incident on the status screen.")
        case "resolved": return IvyLocalizedString("STATUS_STEP_RESOLVED", comment: "Step of an incident or notice on the status screen.")
        case "scheduled": return IvyLocalizedString("STATUS_STEP_SCHEDULED", comment: "Step of maintenance on the status screen.")
        case "in_progress": return IvyLocalizedString("STATUS_STEP_IN_PROGRESS", comment: "Step of maintenance on the status screen.")
        case "completed": return IvyLocalizedString("STATUS_STEP_COMPLETED", comment: "Step of maintenance on the status screen.")
        case "posted": return IvyLocalizedString("STATUS_STEP_POSTED", comment: "Step of a notice on the status screen.")
        default: return step
        }
    }

    /// "2 h 5 min down · 40 min some trouble · 86.98 % up", or "Working all
    /// day", or "No data".
    static func daySummary(_ day: IvyStatusReport.Day) -> String {
        guard let minutes = day.minutes, minutes.total > 0 else {
            return IvyLocalizedString("STATUS_DAY_NO_DATA", comment: "A day without data on the status screen.")
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        func duration(_ value: Int) -> String { formatter.string(from: TimeInterval(value * 60)) ?? "\(value)" }
        var parts = [String]()
        if minutes.down > 0 {
            parts.append(String(format: IvyLocalizedString("STATUS_DAY_DOWN_FORMAT", comment: "How long a service was down on a day. Embeds {{ a duration }}."), duration(minutes.down)))
        }
        if minutes.degraded > 0 {
            parts.append(String(format: IvyLocalizedString("STATUS_DAY_DEGRADED_FORMAT", comment: "How long a service had trouble on a day. Embeds {{ a duration }}."), duration(minutes.degraded)))
        }
        if minutes.maintenance > 0 {
            parts.append(String(format: IvyLocalizedString("STATUS_DAY_MAINTENANCE_FORMAT", comment: "How long a service was under maintenance on a day. Embeds {{ a duration }}."), duration(minutes.maintenance)))
        }
        guard !parts.isEmpty else {
            return IvyLocalizedString("STATUS_DAY_ALL_WORKING", comment: "A day on the status screen when everything worked.")
        }
        parts.append(String(format: IvyLocalizedString("STATUS_UP_FORMAT", comment: "Share of time a service was up. Embeds {{ a percentage }}."), percent(Double(minutes.total - minutes.down) / Double(minutes.total) * 100)))
        return parts.joined(separator: " · ")
    }

    /// The share of checked minutes a service wasn't down, nil without data.
    static func uptime(_ days: [IvyStatusReport.Day]) -> Double? {
        let minutes = days.compactMap(\.minutes)
        let total = minutes.reduce(0) { $0 + $1.total }
        guard total > 0 else { return nil }
        return Double(total - minutes.reduce(0) { $0 + $1.down }) / Double(total) * 100
    }

    static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " %"
    }

    /// The date of a day as "Thu, Oct 30"; days are UTC like on the page.
    static func dayDate(_ day: IvyStatusReport.Day) -> String {
        guard let date = IvyStatusReport.parseDate(day.date + "T12:00:00Z") else {
            return day.date
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }
}

// MARK: - Hero

/// The summary on top, tinted in the status's tone, with buttons when the
/// status can't be loaded.
final class IvyStatusHeroView: UIView {

    struct State {
        let tone: IvyTone?
        let title: String
        let detail: String?
        let showsRetry: Bool
        let showsBrowser: Bool
    }

    var onRetry: (() -> Void)?
    var onOpenInBrowser: (() -> Void)?

    private let card = UIView()
    private let dot = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let buttons = UIStackView()
    private lazy var retryButton = button(title: IvyLocalizedString("STATUS_PAGE_RETRY", comment: "Button that tries to load Ivy Status again.")) { [weak self] in self?.onRetry?() }
    private lazy var browserButton = button(title: IvyStatusViewController.openInBrowserTitle) { [weak self] in self?.onOpenInBrowser?() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        preservesSuperviewLayoutMargins = true
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        dot.layer.cornerRadius = 7
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        detailLabel.font = .dynamicTypeSubheadline
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubviews([retryButton, browserButton, UIView()])

        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel, buttons])
        texts.axis = .vertical
        texts.spacing = 4
        texts.setCustomSpacing(12, after: detailLabel)
        let row = UIStackView(arrangedSubviews: [dot, texts])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 14
        dot.widthAnchor.constraint(equalToConstant: 14).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 14).isActive = true
        card.addSubview(row)
        row.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 18, left: 20, bottom: 18, right: 20))
        addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            card.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            dot.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: 7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func button(title: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        var text = AttributedString(title)
        text.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        configuration.attributedTitle = text
        return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    }

    func update(state: State) {
        if let tone = state.tone {
            card.backgroundColor = tone.background
            dot.backgroundColor = tone.strong
            titleLabel.textColor = tone.text
            detailLabel.textColor = tone.strong
        } else {
            card.backgroundColor = .Signal.secondaryGroupedBackground
            dot.backgroundColor = .Signal.secondaryLabel
            titleLabel.textColor = .Signal.label
            detailLabel.textColor = .Signal.secondaryLabel
        }
        for button in [retryButton, browserButton] {
            button.configuration?.baseBackgroundColor = state.tone?.button ?? .Signal.secondaryFill
            button.configuration?.baseForegroundColor = state.tone?.tagText ?? .Signal.label
        }
        titleLabel.text = state.title
        detailLabel.text = state.detail
        detailLabel.isHidden = state.detail?.isEmpty ?? true
        retryButton.isHidden = !state.showsRetry
        browserButton.isHidden = !state.showsBrowser
        buttons.isHidden = !state.showsRetry && !state.showsBrowser
    }
}

// MARK: - Service

/// A service: its name, what it does and its state; tapped, its 90 days
/// with details for a chosen day.
final class IvyStatusServiceCell: UITableViewCell {

    static let reuseIdentifier = "IvyStatusServiceCell"

    private let nameLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let chip = IvyTagLabel()
    private let foldLabel = UILabel()
    private let bars = IvyStatusDayBars()
    private let scale = UIStackView()
    private let dayLabel = UILabel()
    private let expandedStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        nameLabel.font = UIFont.dynamicTypeBody.semibold()
        nameLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.font = .dynamicTypeFootnote
        descriptionLabel.textColor = .Signal.secondaryLabel
        descriptionLabel.numberOfLines = 0
        descriptionLabel.adjustsFontForContentSizeCategory = true
        foldLabel.font = .dynamicTypeFootnote
        foldLabel.textColor = .Signal.secondaryLabel
        foldLabel.adjustsFontForContentSizeCategory = true
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        chip.setContentHuggingPriority(.required, for: .horizontal)

        let start = UILabel()
        start.text = IvyLocalizedString("STATUS_PAGE_90_DAYS_AGO", comment: "Start of the 90-day bars on the status screen.")
        let end = UILabel()
        end.text = IvyLocalizedString("STATUS_PAGE_TODAY", comment: "End of the 90-day bars on the status screen.")
        for label in [start, end] {
            label.font = .dynamicTypeCaption1Clamped
            label.textColor = .Signal.secondaryLabel
        }
        scale.addArrangedSubviews([start, UIView(), end])
        dayLabel.font = .dynamicTypeFootnote
        dayLabel.textColor = .Signal.label
        dayLabel.numberOfLines = 0
        bars.heightAnchor.constraint(equalToConstant: 26).isActive = true
        expandedStack.axis = .vertical
        expandedStack.spacing = 6
        expandedStack.addArrangedSubviews([bars, scale, dayLabel])

        let texts = UIStackView(arrangedSubviews: [nameLabel, descriptionLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let top = UIStackView(arrangedSubviews: [texts, chip])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 10
        let stack = UIStackView(arrangedSubviews: [top, foldLabel, expandedStack])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(component: IvyStatusReport.Component, isExpanded: Bool, isStale: Bool, selectedDay: Int?, onSelectDay: @escaping (Int) -> Void) {
        let name = IvyStatusTexts.name(id: component.id, fallback: component.name)
        nameLabel.text = name
        var description = IvyStatusTexts.description(id: component.id, fallback: component.description)
        if let detail = component.detail, let range = detail.range(of: #"\d+ ms"#, options: .regularExpression) {
            description += " · " + detail[range]
        }
        descriptionLabel.text = description
        let tone = IvyStatusTexts.tone(for: component.status)
        chip.text = IvyStatusTexts.chip(component.status)
        chip.textColor = tone?.tagText ?? .Signal.secondaryLabel
        chip.backgroundColor = tone?.button ?? .Signal.secondaryFill
        contentView.alpha = isStale ? 0.6 : 1

        let days = component.days ?? []
        let uptime = IvyStatusTexts.uptime(days).map {
            String(format: IvyLocalizedString("STATUS_UP_FORMAT", comment: "Share of time a service was up. Embeds {{ a percentage }}."), IvyStatusTexts.percent($0))
        } ?? IvyLocalizedString("STATUS_DAY_NO_DATA", comment: "A day without data on the status screen.")
        let chevron = isStale ? "" : (isExpanded ? "⌄  " : "›  ")
        foldLabel.text = chevron + IvyLocalizedString("STATUS_PAGE_LAST_90_DAYS", comment: "Label of a service's 90 days on the status screen.") + " · " + uptime
        foldLabel.isHidden = isStale

        expandedStack.isHidden = !isExpanded
        if isExpanded {
            bars.update(days: days, selected: selectedDay)
            bars.onSelect = onSelectDay
            if let selectedDay, days.indices.contains(selectedDay) {
                dayLabel.text = IvyStatusTexts.dayDate(days[selectedDay]) + " · " + IvyStatusTexts.daySummary(days[selectedDay])
            } else {
                dayLabel.text = IvyLocalizedString("STATUS_PAGE_TAP_A_DAY", comment: "Hint under the 90-day bars on the status screen.")
            }
        }
        accessibilityLabel = [name, description, chip.text].compactMap { $0 }.joined(separator: ", ")
        accessibilityHint = isStale ? nil : foldLabel.text
    }
}

/// 90 bars, green with the problem's colour glowing from the top the
/// longer it lasted, as on the status page.
final class IvyStatusDayBars: UIView {

    var onSelect: ((Int) -> Void)?

    private var bars = [CAGradientLayer]()
    private var days = [IvyStatusReport.Day]()
    private var selected: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap(_:))))
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(days: [IvyStatusReport.Day], selected: Int?) {
        self.days = days
        self.selected = selected
        bars.forEach { $0.removeFromSuperlayer() }
        bars = days.map { _ in
            let layer = CAGradientLayer()
            layer.cornerRadius = 1.5
            layer.startPoint = CGPoint(x: 0.5, y: 1)
            layer.endPoint = CGPoint(x: 0.5, y: 0)
            self.layer.addSublayer(layer)
            return layer
        }
        setNeedsLayout()
    }

    static func color(for status: String) -> UIColor {
        IvyStatusTexts.tone(for: status)?.strong ?? .Signal.secondaryFill
    }

    /// The gradient for a day: bottom to top.
    static func gradient(for day: IvyStatusReport.Day) -> (colors: [UIColor], locations: [Double]) {
        let base = color(for: day.status)
        guard let minutes = day.minutes, minutes.total > 0, day.status != "ok", day.status != "none" else {
            return ([base, base], [0, 1])
        }
        let share = Double(minutes.maintenance + minutes.degraded + minutes.down) / Double(minutes.total) * 100
        if share >= 50 {
            return ([base, base], [0, 1])
        }
        let green = IvyTone.green.strong
        let reach = max(share, 14)
        return ([green, green, base], [0, max(100 - reach * 2.2, 0) / 100, 1])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bars.isEmpty else { return }
        let gap: CGFloat = 1.5
        let width = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        for (index, layer) in bars.enumerated() {
            layer.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
            let gradient = Self.gradient(for: days[index])
            layer.colors = gradient.colors.map { $0.resolvedColor(with: traitCollection).cgColor }
            layer.locations = gradient.locations.map { NSNumber(value: $0) }
            layer.borderWidth = index == selected ? 1.5 : 0
            layer.borderColor = UIColor.Signal.label.resolvedColor(with: traitCollection).cgColor
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    @objc
    private func didTap(_ tap: UITapGestureRecognizer) {
        guard !days.isEmpty, bounds.width > 0 else { return }
        let index = Int(tap.location(in: self).x / bounds.width * CGFloat(days.count))
        onSelect?(min(max(index, 0), days.count - 1))
    }
}

// MARK: - Measurements

/// The four measurements as tiles.
final class IvyStatusMetricsCell: UITableViewCell {

    static let reuseIdentifier = "IvyStatusMetricsCell"

    private let grid = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        selectionStyle = .none
        grid.axis = .vertical
        grid.spacing = 10
        contentView.addSubview(grid)
        grid.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ metrics: IvyStatusReport.Metrics) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let tiles = [
            tile(IvyLocalizedString("STATUS_METRIC_UPTIME_30", comment: "Measurement on the status screen: uptime over 30 days."), metrics.uptime30.map(IvyStatusTexts.percent), nil),
            tile(IvyLocalizedString("STATUS_METRIC_UPTIME_90", comment: "Measurement on the status screen: uptime over 90 days."), metrics.uptime90.map(IvyStatusTexts.percent), nil),
            tile(
                IvyLocalizedString("STATUS_METRIC_WAKE", comment: "Measurement on the status screen: how long Apple takes to accept a wake-up."),
                metrics.wakeMedianMs.map { $0 < 1000 ? "\(Int($0.rounded())) ms" : String(format: "%.1f s", $0 / 1000) },
                IvyLocalizedString("STATUS_METRIC_WAKE_HINT", comment: "Hint under the wake-up time on the status screen."),
            ),
            tile(
                IvyLocalizedString("STATUS_METRIC_ACCEPTED", comment: "Measurement on the status screen: share of wake-ups Apple accepted."),
                metrics.acceptance24h.map(IvyStatusTexts.percent),
                IvyLocalizedString("STATUS_METRIC_LAST_24H", comment: "Hint under a measurement on the status screen: the last 24 hours."),
            ),
        ]
        for pair in stride(from: 0, to: tiles.count, by: 2) {
            let row = UIStackView(arrangedSubviews: Array(tiles[pair..<min(pair + 2, tiles.count)]))
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            grid.addArrangedSubview(row)
        }
    }

    private func tile(_ title: String, _ value: String?, _ hint: String?) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title.localizedUppercase
        titleLabel.font = UIFont.dynamicTypeCaption2Clamped.semibold()
        titleLabel.textColor = .Signal.secondaryLabel
        titleLabel.numberOfLines = 2
        let valueLabel = UILabel()
        valueLabel.text = value ?? "–"
        valueLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        valueLabel.adjustsFontSizeToFitWidth = true
        let hintLabel = UILabel()
        hintLabel.text = hint
        hintLabel.font = .dynamicTypeCaption1Clamped
        hintLabel.textColor = .Signal.secondaryLabel
        hintLabel.isHidden = hint == nil
        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel, hintLabel])
        stack.axis = .vertical
        stack.spacing = 2
        let tile = UIView()
        tile.backgroundColor = .Signal.secondaryGroupedBackground
        tile.layer.cornerRadius = 18
        tile.layer.cornerCurve = .continuous
        tile.addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        tile.isAccessibilityElement = true
        tile.accessibilityLabel = [title, value ?? "–", hint].compactMap { $0 }.joined(separator: ", ")
        return tile
    }
}

// MARK: - Post

/// An incident, maintenance or notice with its updates, newest first.
final class IvyStatusPostCell: UITableViewCell {

    static let reuseIdentifier = "IvyStatusPostCell"

    private let edge = UIView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let updates = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = UIFont.dynamicTypeBody.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        metaLabel.font = .dynamicTypeFootnote
        metaLabel.textColor = .Signal.secondaryLabel
        metaLabel.numberOfLines = 0
        metaLabel.adjustsFontForContentSizeCategory = true
        updates.axis = .vertical
        updates.spacing = 8
        let stack = UIStackView(arrangedSubviews: [titleLabel, metaLabel, updates])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(10, after: metaLabel)
        contentView.addSubview(edge)
        contentView.addSubview(stack)
        edge.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            edge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            edge.topAnchor.constraint(equalTo: contentView.topAnchor),
            edge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: 4),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(post: IvyStatusReport.Post, report: IvyStatusReport?) {
        edge.backgroundColor = Self.tone(for: post).strong
        titleLabel.text = post.title
        var meta = [IvyStatusTexts.kind(post.kind)]
        if post.kind == "maintenance", let starts = post.starts, let ends = post.ends {
            meta.append(DateIntervalFormatter.localizedString(from: starts, to: ends))
        }
        let services = IvyStatusTexts.names(post.components ?? [], report: report)
        if !services.isEmpty {
            meta.append(services.joined(separator: ", "))
        }
        metaLabel.text = meta.joined(separator: " · ")

        updates.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for update in (post.updates ?? []).reversed() {
            let heading = NSMutableAttributedString(string: IvyStatusTexts.step(update.step), attributes: [.font: UIFont.dynamicTypeSubheadline.semibold(), .foregroundColor: UIColor.Signal.label])
            heading.append(NSAttributedString(
                string: "  " + DateFormatter.localizedString(from: update.time, dateStyle: .short, timeStyle: .short),
                attributes: [.font: UIFont.dynamicTypeFootnote, .foregroundColor: UIColor.Signal.secondaryLabel],
            ))
            let headingLabel = UILabel()
            headingLabel.attributedText = heading
            headingLabel.numberOfLines = 0
            let entry = UIStackView(arrangedSubviews: [headingLabel])
            entry.axis = .vertical
            entry.spacing = 2
            if !update.message.isEmpty {
                let message = UILabel()
                message.text = update.message
                message.font = .dynamicTypeSubheadline
                message.textColor = .Signal.secondaryLabel
                message.numberOfLines = 0
                entry.addArrangedSubview(message)
            }
            updates.addArrangedSubview(entry)
        }
    }

    private static func tone(for post: IvyStatusReport.Post) -> IvyTone {
        switch post.kind {
        case "incident": return post.impact == "major" ? .red : .brown
        case "maintenance": return .blue
        default: return .green
        }
    }
}

private extension DateIntervalFormatter {
    static func localizedString(from start: Date, to end: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: start, to: end)
    }
}
