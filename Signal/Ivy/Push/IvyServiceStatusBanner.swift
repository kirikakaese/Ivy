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

    var bannerImage: UIImage? {
        switch level {
        case .unreachable, .down, .degraded: return UIImage(systemName: "wifi.exclamationmark")
        case .maintenance: return UIImage(systemName: "wrench.and.screwdriver")
        case .notice: return UIImage(systemName: "info.circle")
        }
    }
}

// MARK: - Banner

/// The chat list banner, in the style of the backup progress banner. Tap
/// it for Ivy Status; the chevron collapses it to its title.
final class IvyServiceStatusBanner: ChatListBackupProgressView {

    /// Called when the banner's height or visibility changed.
    var onLayoutChange: (() -> Void)?
    weak var presentingViewController: UIViewController?

    /// Holds the banner with the chat list's margins; hidden when all is well.
    let container = UIView()

    private lazy var chevronButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .Signal.secondaryLabel
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.toggleCollapsed()
        })
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 24),
            button.widthAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }()

    override init() {
        super.init()
        initializeTrailingAccessoryViews([chevronButton])
        container.addSubview(self)
        autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openStatusPage)))
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: IvyServiceStatusMonitor.statusDidChange, object: nil)
        update()
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented")
    }

    @objc
    func update() {
        let monitor = IvyServiceStatusMonitor.shared
        guard let status = monitor.status else {
            setHidden(true)
            return
        }
        let isCollapsed = monitor.isCollapsed
        configure(
            leadingAccessoryImage: status.bannerImage ?? UIImage(),
            leadingAccessoryImageTintColor: status.level == .notice ? .Signal.label : .Signal.orange,
            titleLabelText: status.bannerTitle,
            progressLabelText: isCollapsed ? nil : status.bannerDetail,
            trailingAccessoryView: status.bannerDetail == nil ? nil : chevronButton,
        )
        chevronButton.configuration?.image = UIImage(systemName: isCollapsed ? "chevron.down" : "chevron.up")
        chevronButton.accessibilityLabel = isCollapsed
            ? IvyLocalizedString("SERVICE_STATUS_EXPAND", comment: "Accessibility label of the button that shows the chat list banner's details.")
            : IvyLocalizedString("SERVICE_STATUS_COLLAPSE", comment: "Accessibility label of the button that hides the chat list banner's details.")
        setHidden(false)
    }

    private func setHidden(_ hidden: Bool) {
        container.isHidden = hidden
        onLayoutChange?()
    }

    private func toggleCollapsed() {
        IvyServiceStatusMonitor.shared.isCollapsed.toggle()
        update()
    }

    @objc
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
