//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// On the Mac, the system shows the tabs at the top of the window, above the
/// conversation. Ivy hides them there and shows a switcher at the bottom of
/// the sidebar instead: Home, Chats, Calendar, Calls.
extension HomeTabBarController {

    static var ivyUsesTabSwitcher: Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }

    /// Room the switcher takes at the bottom of the lists.
    static let ivyTabSwitcherInset: CGFloat = 56

    private var ivySwitcherTabs: [Tabs] {
        ivyShownTabs
    }

    /// Opens the section chosen in Settings, Chats by default.
    func ivySelectStartTab() {
        let section = SSKEnvironment.shared.databaseStorageRef.read { tx in IvyHomeSettings.startSection(tx: tx) }
        selectedHomeTab = Tabs(section)
    }

    func ivyInstallTabSwitcher() {
        guard Self.ivyUsesTabSwitcher else {
            return
        }
        if #available(iOS 18, *) {
            isTabBarHidden = true
        }
        tabBar.isHidden = true

        let switcher = ivyTabSwitcher
        for (index, tab) in ivySwitcherTabs.enumerated() {
            switcher.insertSegment(withTitle: tab.title, at: index, animated: false)
        }
        switcher.apportionsSegmentWidthsByContent = true
        ivyUpdateTabSwitcherSelection()
        switcher.addAction(UIAction { [weak self] _ in
            self?.ivyDidChangeTabSwitcher()
        }, for: .valueChanged)

        view.addSubview(switcher)
        switcher.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            switcher.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            switcher.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            switcher.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            switcher.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])

        for navigationController in [chatListNavController, callsListNavController, storiesNavController, ivyHomeNavController, ivyCalendarNavController] {
            navigationController.additionalSafeAreaInsets.bottom += Self.ivyTabSwitcherInset
        }
    }

    func ivyUpdateTabSwitcherSelection() {
        guard Self.ivyUsesTabSwitcher else {
            return
        }
        ivyTabSwitcher.selectedSegmentIndex = ivySwitcherTabs.firstIndex(of: selectedHomeTab) ?? UISegmentedControl.noSegment
    }

    func ivySetTabSwitcherHidden(_ hidden: Bool, animated: Bool) {
        let switcher = ivyTabSwitcher
        guard switcher.isHidden != hidden else {
            return
        }
        guard animated else {
            switcher.isHidden = hidden
            return
        }
        switcher.isHidden = false
        switcher.alpha = hidden ? 1 : 0
        UIView.animate(withDuration: 0.15, animations: {
            switcher.alpha = hidden ? 0 : 1
        }, completion: { _ in
            switcher.isHidden = hidden
            switcher.alpha = 1
        })
    }

    /// Shows the unread chats and missed calls next to the tab names.
    func ivyUpdateTabSwitcherBadges(unreadChatCount: UInt, unreadCallsCount: UInt) {
        guard Self.ivyUsesTabSwitcher else {
            return
        }
        for (index, tab) in ivySwitcherTabs.enumerated() {
            let count: UInt
            switch tab {
            case .chatList: count = unreadChatCount
            case .calls: count = unreadCallsCount
            case .stories, .home, .calendar: count = 0
            }
            let title = count > 0 ? "\(tab.title) \(count.formatted())" : tab.title
            ivyTabSwitcher.setTitle(title, forSegmentAt: index)
        }
    }

    private func ivyDidChangeTabSwitcher() {
        let index = ivyTabSwitcher.selectedSegmentIndex
        guard ivySwitcherTabs.indices.contains(index) else {
            return
        }
        selectedHomeTab = ivySwitcherTabs[index]
        if let selectedViewController {
            tabBarController(self, didSelect: selectedViewController)
        }
    }
}

// MARK: - Sections

extension HomeTabBarController.Tabs {

    init(_ section: IvySection) {
        switch section {
        case .home: self = .home
        case .chats: self = .chatList
        case .calendar: self = .calendar
        case .calls: self = .calls
        }
    }

    var ivyTitle: String {
        switch self {
        case .home:
            return IvyLocalizedString("HOME_TITLE", comment: "Title of the Home section with today's agenda, tasks and important messages.")
        case .calendar:
            return IvyCalendarUI.calendarTitle
        case .chatList, .calls, .stories:
            return title
        }
    }

    var ivyImage: UIImage? {
        switch self {
        case .home:
            return UIImage(systemName: "house")
        case .calendar:
            return UIImage(systemName: "calendar")
        case .chatList, .calls, .stories:
            return image
        }
    }
}
