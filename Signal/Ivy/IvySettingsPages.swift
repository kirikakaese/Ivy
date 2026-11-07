//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Ivy's pages in Settings, grouped by what they're for: Start and Tabs,
/// Controls, Folders, Calendar and Tasks, Reminders, Snippets, and Ivy Sync
/// and Backup. Each row has an icon and a name that says what's inside.
enum IvySettingsPage: CaseIterable {
    case startAndTabs
    case controls
    case folders
    case calendarAndTasks
    case reminders
    case snippets
    case syncAndBackup

    var title: String {
        switch self {
        case .startAndTabs: IvyLocalizedString("HOME_SETTINGS_TITLE", comment: "Title of the settings for Home and navigation.")
        case .controls: IvyLocalizedString("CONTROLS_SETTINGS_TITLE", comment: "Title of the settings for how Ivy is used by hand: reaction bar, gestures, message menu.")
        case .folders: IvyLocalizedString("CHAT_FOLDERS_TITLE", comment: "Title of the chat folder settings.")
        case .calendarAndTasks: IvyLocalizedString("CALENDAR_TASKS_SETTINGS_TITLE", comment: "Title of the settings for the calendar and tasks.")
        case .reminders: IvyLocalizedString("REMINDERS_TITLE", comment: "Title of the list of reminders.")
        case .snippets: IvySnippetsViewController.title
        case .syncAndBackup: IvyLocalizedString("IVY_DATA_TITLE", comment: "Title of the settings for Ivy's own data: folders, reminders, sync and backup.")
        }
    }

    var symbol: String {
        switch self {
        case .startAndTabs: "house"
        case .controls: "hand.raised"
        case .folders: "folder"
        case .calendarAndTasks: "calendar"
        case .reminders: "bell"
        case .snippets: "text.quote"
        case .syncAndBackup: "arrow.triangle.2.circlepath"
        }
    }

    @MainActor
    func makeViewController() -> UIViewController {
        switch self {
        case .startAndTabs: IvyHomeSettingsViewController()
        case .controls: IvyControlsSettingsViewController()
        case .folders: ChatFoldersSettingsViewController()
        case .calendarAndTasks: IvyCalendarTasksSettingsViewController()
        case .reminders: IvyRemindersViewController()
        case .snippets: IvySnippetsViewController()
        case .syncAndBackup: IvyDataSettingsViewController()
        }
    }

    /// The row for this page in the main settings list.
    @MainActor
    func item(in navigationController: @escaping () -> UINavigationController?) -> OWSTableItem {
        IvySettingsRow.item(symbol: symbol, title: title) {
            navigationController()?.pushViewController(self.makeViewController(), animated: true)
        }
    }
}

/// A settings row with an SF Symbol in the style of Signal's settings icons.
enum IvySettingsRow {
    @MainActor
    static func item(symbol: String, title: String, accessoryText: String? = nil, action: @escaping () -> Void) -> OWSTableItem {
        OWSTableItem(
            customCellBlock: {
                let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
                let image = UIImage(systemName: symbol, withConfiguration: configuration)
                return OWSTableItem.buildImageCell(
                    image: image,
                    tintColor: Theme.primaryIconColor,
                    itemName: title,
                    accessoryText: accessoryText,
                    accessoryType: .disclosureIndicator,
                )
            },
            actionBlock: action,
        )
    }
}

// MARK: - Controls

/// Settings > Controls: the hand, the reaction bar, double-tap, swiping
/// left, the message menu, the Mac shortcut and the tips.
final class IvyControlsSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvySettingsPage.controls.title
        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        // Hand, reaction bar position and swipe are for touch screens.
        if IvyHand.appliesHere {
            ivyAddHandSection(to: contents)
            ivyAddReactionBarSection(to: contents)
        }
        ivyAddDoubleTapSection(to: contents)
        if IvyHand.appliesHere {
            ivyAddSwipeLeftSection(to: contents)
        }
        ivyAddMessageMenuSection(to: contents)
#if targetEnvironment(macCatalyst)
        let macSection = OWSTableSection()
        macSection.add(.disclosureItem(
            withText: IvyHotKeySettingsViewController.title,
            accessoryText: IvyHotKey.current.title,
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyHotKeySettingsViewController(), animated: true)
            },
        ))
        contents.add(macSection)
#endif
        ivyAddTipsSection(to: contents)
        self.contents = contents
    }
}

// MARK: - Calendar and tasks

/// Settings > Calendar and Tasks: syncing with Apple's apps and the weekly
/// review. The calendar and the tasks themselves are in their tabs.
final class IvyCalendarTasksSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvySettingsPage.calendarAndTasks.title
        let contents = OWSTableContents()
        let section = OWSTableSection()
        section.footerTitle = IvyLocalizedString("CALENDAR_TASKS_SETTINGS_FOOTER", comment: "Footer of the calendar and tasks settings: the calendar and tasks themselves are in their tabs.")
        section.add(.disclosureItem(
            withText: IvyAppleSyncSettingsViewController.title,
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyAppleSyncSettingsViewController(), animated: true)
            },
        ))
        section.add(.disclosureItem(
            withText: IvyWeeklyReviewViewController.title,
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyWeeklyReviewSettingsViewController(), animated: true)
            },
        ))
        contents.add(section)
        self.contents = contents
    }
}

// MARK: - Empty states

/// The same empty state on every Ivy list: a symbol, a title and a line
/// on how to add something.
enum IvyEmptyState {
    static func view(symbol: String, title: String, text: String?) -> UIView {
        let iconView = UIImageView(image: UIImage(systemName: symbol))
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 36, weight: .light)
        iconView.tintColor = .Signal.tertiaryLabel
        iconView.contentMode = .center

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let stackView = UIStackView(arrangedSubviews: [iconView, titleLabel])
        if let text {
            let bodyLabel = UILabel()
            bodyLabel.text = text
            bodyLabel.font = .dynamicTypeSubheadline
            bodyLabel.textColor = .Signal.secondaryLabel
            bodyLabel.textAlignment = .center
            bodyLabel.numberOfLines = 0
            stackView.addArrangedSubview(bodyLabel)
        }
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.setCustomSpacing(16, after: iconView)

        let container = UIView()
        container.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: container.layoutMarginsGuide.leadingAnchor, constant: 16),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
        return container
    }
}
