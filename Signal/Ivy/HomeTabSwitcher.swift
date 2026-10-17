//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// On the Mac, the system shows the Chats and Calls tabs at the top of the
/// window, above the conversation. Ivy hides them there and shows a switcher
/// at the bottom of the chat list instead.
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
        IvyConfiguration.showsStories ? [.chatList, .calls, .stories] : [.chatList, .calls]
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

        for navigationController in [chatListNavController, callsListNavController, storiesNavController] {
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
            case .stories: count = 0
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
