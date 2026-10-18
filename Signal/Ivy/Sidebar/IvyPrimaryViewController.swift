//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The left part of the window: the sidebar, then the list of the open
/// section (chats, calls, calendar or Home). Next to it the split view shows
/// the conversation, so the window has three columns like Mail.
///
/// The sidebar shows on the Mac and on an iPad that is wide enough. Without
/// it, the sections are tabs at the bottom, as on the iPhone.
final class IvyPrimaryViewController: UIViewController {

    let homeVC: HomeTabBarController
    private let sidebar: IvySidebarViewController
    private let separator = UIView()
    private var homeLeadingConstraint: NSLayoutConstraint!

    private(set) var isSidebarShown = false

    private var separatorWidth: CGFloat { 1 / max(traitCollection.displayScale, 1) }

    static var sidebarWidth: CGFloat {
#if targetEnvironment(macCatalyst)
        return 220
#else
        return 260
#endif
    }

    /// Below this window width an iPad shows tabs instead.
    private static let minimumWindowWidthForSidebar: CGFloat = 1000

    private static let hiddenByUserKey = "IvySidebarHidden"

    init(homeVC: HomeTabBarController) {
        self.homeVC = homeVC
        self.sidebar = IvySidebarViewController(homeVC: homeVC)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        addChild(sidebar)
        view.addSubview(sidebar.view)
        sidebar.didMove(toParent: self)

        addChild(homeVC)
        view.addSubview(homeVC.view)
        homeVC.didMove(toParent: self)

        separator.backgroundColor = .separator
        view.addSubview(separator)

        for subview in [sidebar.view!, homeVC.view!, separator] {
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        homeLeadingConstraint = homeVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        NSLayoutConstraint.activate([
            sidebar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.view.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.view.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            separator.leadingAnchor.constraint(equalTo: sidebar.view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: separatorWidth),
            homeLeadingConstraint,
            homeVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            homeVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            homeVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        sidebar.view.isHidden = true
        separator.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Self.configureWindow(view.window?.windowScene)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateSidebarVisibility()
    }

    // MARK: - Showing the sidebar

    private var isHiddenByUser: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hiddenByUserKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hiddenByUserKey) }
    }

    /// Whether the sidebar fits: never when the window shows one column.
    private var canShowSidebar: Bool {
        guard let splitViewController, !splitViewController.isCollapsed else {
            return false
        }
#if targetEnvironment(macCatalyst)
        return true
#else
        return (view.window?.bounds.width ?? 0) >= Self.minimumWindowWidthForSidebar
#endif
    }

    /// The View menu's "Show Sidebar" / "Hide Sidebar".
    func toggleSidebar() {
        isHiddenByUser = isSidebarShown
        updateSidebarVisibility()
    }

    func updateSidebarVisibility() {
        let shows = canShowSidebar && !isHiddenByUser
        guard shows != isSidebarShown else {
            return
        }
        isSidebarShown = shows
        sidebar.view.isHidden = !shows
        separator.isHidden = !shows
        homeLeadingConstraint.constant = shows ? Self.sidebarWidth + separatorWidth : 0
        // The list keeps its own background; only the sidebar is translucent.
        homeVC.view.backgroundColor = shows ? Theme.backgroundColor : nil
        homeVC.ivySetSidebarShown(shows)
        (splitViewController as? ConversationSplitViewController)?.ivyUpdateColumnWidths(sidebarWidth: shows ? Self.sidebarWidth : 0)
        homeVC.chatListViewController.ivyUpdateChatFolderBar()
    }

    // MARK: - Window

    /// On the Mac: no title in the title bar, which only repeated "Ivy", and
    /// a size that leaves room for all three columns.
    static func configureWindow(_ windowScene: UIWindowScene?) {
#if targetEnvironment(macCatalyst)
        guard let windowScene else {
            return
        }
        windowScene.titlebar?.titleVisibility = .hidden
        windowScene.titlebar?.toolbar = nil
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 560)
#endif
    }
}

// MARK: - Split view

extension ConversationSplitViewController {

    /// Room for the sidebar next to the list.
    func ivyUpdateColumnWidths(sidebarWidth: CGFloat) {
        minimumPrimaryColumnWidth = 280 + sidebarWidth
        maximumPrimaryColumnWidth = 400 + sidebarWidth
        preferredPrimaryColumnWidthFraction = sidebarWidth > 0 ? 0.5 : 0.42
    }

    var ivyPrimaryViewController: IvyPrimaryViewController? {
        viewControllers.first as? IvyPrimaryViewController
    }

    @objc
    func ivyToggleSidebar() {
        ivyPrimaryViewController?.toggleSidebar()
    }

    /// "Show Sidebar" or "Hide Sidebar" in the View menu.
    override func validate(_ command: UICommand) {
        super.validate(command)
        if command.action == #selector(ivyToggleSidebar) {
            command.title = ivyPrimaryViewController?.isSidebarShown == true
                ? IvyLocalizedString("SIDEBAR_HIDE", comment: "Menu command that hides the sidebar.")
                : IvyLocalizedString("SIDEBAR_SHOW", comment: "Menu command that shows the sidebar.")
        }
    }
}
