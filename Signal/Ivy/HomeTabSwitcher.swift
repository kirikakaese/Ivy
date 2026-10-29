//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The sections: Home, Chats, Calendar, Calls. On the iPhone and a narrow
/// iPad they are tabs; on the Mac and a wide iPad the sidebar shows them
/// instead (see IvyPrimaryViewController).
extension HomeTabBarController {

    /// Opens the section chosen in Settings, Chats by default.
    func ivySelectStartTab() {
        let section = SSKEnvironment.shared.databaseStorageRef.read { tx in IvyHomeSettings.startSection(tx: tx) }
        selectedHomeTab = Tabs(section)
    }

    /// Hides the tab bar while the sidebar shows the sections.
    func ivySetSidebarShown(_ shown: Bool) {
        if shown {
            setTabBarHidden(true, animated: false)
        }
        ivyIsSidebarShown = shown
        if #available(iOS 18, *) {
            isTabBarHidden = shown
        }
        tabBar.isHidden = shown
        if !shown {
            setTabBarHidden(false, animated: false)
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

// MARK: - Profile picture

extension HomeTabViewController {

    /// The profile picture that opens Settings, as on Chats and Calls. Only
    /// on a section's first page, not when the page is shown as a sheet.
    func ivyUpdateProfileButton() {
        guard
            navigationController?.viewControllers.first === self,
            navigationController?.presentingViewController == nil
        else {
            return
        }
        navigationItem.leftBarButtonItem = createSettingsBarButtonItem(
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            buildActions: { settingsAction in [settingsAction] },
            showAppSettings: { [weak self] in
                self?.presentFormSheet(AppSettingsViewController.inModalNavigationController(), animated: true)
            },
        )
    }
}
