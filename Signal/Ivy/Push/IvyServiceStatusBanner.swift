//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

/// Keeps Ivy Status up to date while Ivy is open, for the relay this
/// device uses. Problems show as a banner in the chat list and a badge on
/// the profile picture.
@MainActor
final class IvyServiceStatusMonitor: NSObject {

    static let shared = IvyServiceStatusMonitor()

    static let statusDidChange = Notification.Name("IvyServiceStatusDidChange")

    /// How often Ivy asks while it's open.
    static let refreshInterval: TimeInterval = 5 * .minute
    /// How soon Ivy asks again after the relay didn't answer.
    static let retryInterval: TimeInterval = .minute
    /// Failed attempts in a row before Ivy reports the relay as unreachable.
    static let failuresBeforeUnreachable = 2

    private(set) var status: IvyServiceStatus? {
        didSet {
            if status != oldValue {
                NotificationCenter.default.post(name: Self.statusDidChange, object: nil)
            }
        }
    }

    /// The status page to open from the banner.
    private(set) var statusPageURL: URL?

    private var failures = 0
    private var timer: Timer?
    private var isRefreshing = false
    private var isStarted = false

    private override init() {}

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: .OWSApplicationWillResignActive, object: nil)
        if CurrentAppContext().isMainAppAndActive {
            didBecomeActive()
        }
    }

    @objc
    private func didBecomeActive() {
        refresh()
    }

    @objc
    private func willResignActive() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in IvyServiceStatusMonitor.shared.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            guard let relayURL = IvyPushRelay.shared.connection?.relayURL else {
                failures = 0
                statusPageURL = nil
                status = nil
                return
            }
            statusPageURL = IvyPushRelay.statusPageURL(for: relayURL)
            do {
                status = try await IvyServiceStatus.fetch(relayURL: relayURL)
                failures = 0
                schedule(after: Self.refreshInterval)
            } catch {
                // Offline, the relay can't be told apart from the internet.
                if SSKEnvironment.shared.reachabilityManagerRef.isReachable {
                    failures += 1
                    if failures >= Self.failuresBeforeUnreachable {
                        status = .unreachable
                    }
                }
                schedule(after: Self.retryInterval)
            }
        }
    }

    // MARK: - Collapsing

    private static let collapsedKey = "IvyServiceStatusCollapsed"

    /// Collapsing lasts for this problem; a new one shows in full again.
    var isCollapsed: Bool {
        get {
            guard let status else { return false }
            return UserDefaults.standard.string(forKey: Self.collapsedKey) == status.id
        }
        set {
            UserDefaults.standard.set(newValue ? status?.id : nil, forKey: Self.collapsedKey)
        }
    }
}

// MARK: - Texts

extension IvyServiceStatus {

    var bannerTitle: String {
        if let title, !title.isEmpty {
            return title
        }
        switch level {
        case .unreachable:
            return IvyLocalizedString("SERVICE_STATUS_UNREACHABLE_TITLE", comment: "Chat list banner title when Ivy can't reach its push relay.")
        case .down:
            return IvyLocalizedString("SERVICE_STATUS_DOWN_TITLE", comment: "Chat list banner title when Ivy Status reports an outage.")
        case .degraded:
            return IvyLocalizedString("SERVICE_STATUS_DEGRADED_TITLE", comment: "Chat list banner title when Ivy Status reports problems.")
        case .maintenance:
            return IvyLocalizedString("SERVICE_STATUS_MAINTENANCE_TITLE", comment: "Chat list banner title during maintenance of Ivy's services.")
        case .notice:
            return IvyLocalizedString("SERVICE_STATUS_NOTICE_TITLE", comment: "Chat list banner title for a notice from Ivy Status.")
        }
    }

    var bannerDetail: String? {
        var lines = [String]()
        if let detail {
            lines.append(detail)
        } else {
            switch level {
            case .unreachable, .down:
                lines.append(IvyLocalizedString("SERVICE_STATUS_DOWN_DETAIL", comment: "Chat list banner text when instant notifications may not work."))
            case .degraded, .maintenance:
                lines.append(IvyLocalizedString("SERVICE_STATUS_DEGRADED_DETAIL", comment: "Chat list banner text when notifications may be late."))
            case .notice:
                break
            }
        }
        if !components.isEmpty {
            lines.append(String(
                format: IvyLocalizedString("SERVICE_STATUS_AFFECTED_FORMAT", comment: "Chat list banner line naming the affected services. Embeds {{ the services, comma-separated }}."),
                components.joined(separator: ", "),
            ))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

// MARK: - Banner

/// The chat list banner, in the style of Signal's reminders (like "This
/// device is no longer registered"), in a pastel tone of the status page's
/// colour for the problem: its title, details that can be folded away, and
/// a button for Ivy Status.
final class IvyServiceStatusBanner: UIView {

    /// Called when the banner's height or visibility changed.
    var onLayoutChange: (() -> Void)?
    /// What the banner showed last, so only real changes are reported.
    private var shown: String?
    weak var presentingViewController: UIViewController?

    /// Holds the banner in the chat list; hidden when all is well.
    let container = UIView()

    private let backgroundView = UIView()
    private let stack = UIStackView()
    private let textLabel = UILabel()
    private let buttons = UIStackView()
    private lazy var detailsButton = Self.button { [weak self] in self?.toggleCollapsed() }
    private lazy var statusButton = Self.button { [weak self] in self?.openStatusPage() }

    private struct Palette {
        let text: UIColor
        let background: UIColor
        let button: UIColor

        /// Text is the system's in light mode; colours are (light, dark).
        init(darkText: UInt32, background: (UInt32, UInt32), button: (UInt32, UInt32)) {
            self.text = UIColor(light: .Signal.label, dark: UIColor(rgbHex: darkText))
            self.background = UIColor(light: UIColor(rgbHex: background.0), dark: UIColor(rgbHex: background.1))
            self.button = UIColor(light: UIColor(rgbHex: button.0), dark: UIColor(rgbHex: button.1))
        }
    }

    // Trouble uses the warning colours of SignalUI's ReminderView; the
    // others follow the status page in the same pastel strength.
    private static func palette(for level: IvyServiceStatus.Level) -> Palette {
        switch level {
        case .down:
            return Palette(darkText: 0xDE8F87, background: (0xFCEDEB, 0x2A1D1C), button: (0xF6D5D1, 0x422926))
        case .degraded, .unreachable:
            return Palette(darkText: 0xC79869, background: (0xFBF2E9, 0x26221D), button: (0xF4DDC7, 0x392D22))
        case .maintenance:
            return Palette(darkText: 0x8FB0DA, background: (0xEBF2FB, 0x1C222B), button: (0xD3E3F5, 0x26313F))
        case .notice:
            return Palette(darkText: 0x86C29E, background: (0xEBF6EF, 0x1C2520), button: (0xD3EBDC, 0x26372D))
        }
    }

    init() {
        super.init(frame: .zero)
        container.addSubview(self)
        autoPinEdgesToSuperviewEdges()

        layoutMargins = UIEdgeInsets(hMargin: 18, vMargin: 12)
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewMargins()
        if #available(iOS 26, *) {
            backgroundView.layer.cornerRadius = 26
            backgroundView.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 16)
            stack.spacing = 12
        } else {
            backgroundView.layer.cornerRadius = 12
            backgroundView.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 14)
            stack.spacing = 8
        }

        stack.axis = .vertical
        stack.alignment = .trailing
        backgroundView.addSubview(stack)
        stack.autoPinEdgesToSuperviewMargins()

        textLabel.font = .dynamicTypeSubheadline
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.numberOfLines = 0
        stack.addArrangedSubview(textLabel)
        textLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubviews([detailsButton, statusButton])
        stack.addArrangedSubview(buttons)

        statusButton.configuration?.title = IvyLocalizedString("SERVICE_STATUS_OPEN_BUTTON", comment: "Button on the chat list banner that opens the Ivy Status page.")

        NotificationCenter.default.addObserver(self, selector: #selector(update), name: IvyServiceStatusMonitor.statusDidChange, object: nil)
        update()
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented")
    }

    private static func button(_ action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.dynamicTypeSubheadline.medium()
            return attributes
        }
        if #available(iOS 26, *) {
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        } else {
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0)
        }
        return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    }

    @objc
    func update() {
        let monitor = IvyServiceStatusMonitor.shared
        guard let status = monitor.status else {
            container.isHidden = true
            reportChange(nil)
            return
        }
        let isCollapsed = monitor.isCollapsed
        let palette = Self.palette(for: status.level)
        backgroundView.backgroundColor = palette.background

        let text = NSMutableAttributedString(string: status.bannerTitle, attributes: [.font: UIFont.dynamicTypeSubheadline.semibold()])
        if !isCollapsed, let detail = status.bannerDetail {
            text.append(NSAttributedString(string: "\n" + detail, attributes: [.font: UIFont.dynamicTypeSubheadline]))
        }
        textLabel.attributedText = text
        textLabel.textColor = palette.text

        for button in [detailsButton, statusButton] {
            if #available(iOS 26, *) {
                button.configuration?.baseBackgroundColor = palette.button
            } else {
                button.configuration?.baseBackgroundColor = .clear
            }
            button.configuration?.baseForegroundColor = palette.text
        }
        detailsButton.isHidden = status.bannerDetail == nil
        detailsButton.configuration?.title = isCollapsed
            ? IvyLocalizedString("SERVICE_STATUS_EXPAND", comment: "Button on the chat list banner that shows its details.")
            : IvyLocalizedString("SERVICE_STATUS_COLLAPSE", comment: "Button on the chat list banner that hides its details.")

        container.isHidden = false
        reportChange([status.id, status.bannerTitle, String(isCollapsed), status.bannerDetail ?? ""].joined(separator: "\n"))
    }

    private func reportChange(_ state: String?) {
        guard state != shown else {
            return
        }
        shown = state
        onLayoutChange?()
    }

    private func toggleCollapsed() {
        IvyServiceStatusMonitor.shared.isCollapsed.toggle()
        update()
    }

    private func openStatusPage() {
        guard let url = IvyServiceStatusMonitor.shared.statusPageURL, let presentingViewController else {
            return
        }
        presentingViewController.present(SFSafariViewController(url: url), animated: true)
    }
}

// MARK: - Profile picture badge

/// A yellow circle with a "no connection" sign on the profile picture while
/// Ivy Status reports a problem.
final class IvyServiceStatusBadge: UIView {

    /// Adds the badge to `container`, on the top trailing edge of the
    /// profile picture.
    static func add(to container: UIView, on avatarView: UIView, avatarDiameter: CGFloat) {
        let badgeDiameter: CGFloat = avatarDiameter >= 36 ? 18 : 15
        let badge = IvyServiceStatusBadge(diameter: badgeDiameter)
        container.addSubview(badge)
        // As UIView.addCircleBadge: overlapping on a 45° diagonal.
        let overlap: CGFloat = 5
        let centerOffset = (avatarDiameter / 2 + badgeDiameter / 2 - overlap) / CGFloat(2).squareRoot()
        let edgeInset = avatarDiameter / 2 - badgeDiameter / 2 - centerOffset
        badge.autoPinEdge(.top, to: .top, of: avatarView, withOffset: edgeInset)
        badge.autoPinEdge(.trailing, to: .trailing, of: avatarView, withOffset: -edgeInset)
    }

    private init(diameter: CGFloat) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .Signal.yellow
        layer.cornerRadius = diameter / 2
        autoSetDimensions(to: CGSize(square: diameter))

        let imageView = UIImageView(image: UIImage(
            systemName: "wifi.exclamationmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.5, weight: .bold),
        ))
        imageView.tintColor = .black
        imageView.contentMode = .center
        addSubview(imageView)
        imageView.autoCenterInSuperview()

        NotificationCenter.default.addObserver(self, selector: #selector(update), name: IvyServiceStatusMonitor.statusDidChange, object: nil)
        update()
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented")
    }

    @objc
    private func update() {
        isHidden = IvyServiceStatusMonitor.shared.status?.isProblem != true
    }
}
