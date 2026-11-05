//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// One thing Settings can find: its name, where it is, and how to open it.
struct IvySettingsEntry {
    let title: String
    /// The page it's on, shown under the title; nil for pages themselves.
    let place: String?
    let open: @MainActor (UINavigationController) -> Void
}

/// Everything the search field in Settings can find.
enum IvySettingsIndex {

    /// The entries whose name or page contains every word of the query,
    /// ignoring case and accents. Names that start with the query come first.
    static func matches(_ entries: [IvySettingsEntry], query: String) -> [IvySettingsEntry] {
        let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let found = entries.filter { entry in
            let haystack = fold(entry.title + " " + (entry.place ?? ""))
            return words.allSatisfy { haystack.contains($0) }
        }
        let first = fold(words[0])
        return found.sorted { a, b in
            let aStarts = fold(a.title).hasPrefix(first), bStarts = fold(b.title).hasPrefix(first)
            return aStarts && !bStarts
        }
    }

    @MainActor
    static func entries() -> [IvySettingsEntry] {
        func page(_ title: String, _ make: @escaping @MainActor () -> UIViewController) -> IvySettingsEntry {
            IvySettingsEntry(title: title, place: nil) { $0.pushViewController(make(), animated: true) }
        }
        func item(_ title: String, on ivyPage: IvySettingsPage) -> IvySettingsEntry {
            IvySettingsEntry(title: title, place: ivyPage.title) { $0.pushViewController(ivyPage.makeViewController(), animated: true) }
        }
        let chats = OWSLocalizedString("SETTINGS_CHATS", comment: "Title for the 'chats' link in settings.")
        let notifications = OWSLocalizedString("SETTINGS_NOTIFICATIONS", comment: "The title for the notification settings.")
        let privacy = OWSLocalizedString("SETTINGS_PRIVACY_TITLE", comment: "The title for the privacy settings.")

        var result: [IvySettingsEntry] = [
            page(OWSLocalizedString("SETTINGS_ACCOUNT", comment: "Title for the 'account' link in settings.")) { AccountSettingsViewController() },
            page(OWSLocalizedString("SETTINGS_APPEARANCE_TITLE", comment: "The title for the appearance settings.")) { AppearanceSettingsTableViewController() },
            page(chats) { ChatsSettingsViewController() },
            page(notifications) { NotificationSettingsViewController() },
            page(privacy) { PrivacySettingsViewController() },
            page(OWSLocalizedString("SETTINGS_DATA", comment: "Label for the 'data' section of the app settings.")) { DataSettingsTableViewController() },
        ]
        result += IvySettingsPage.allCases.map { ivyPage in page(ivyPage.title) { ivyPage.makeViewController() } }
        result += [
            item(IvyLocalizedString("HAND_TITLE", comment: "Header of the setting that chooses which hand Ivy is used with."), on: .controls),
            item(IvyLocalizedString("REACTION_BAR_POSITION_TITLE", comment: "Header of the setting that chooses where the reaction bar goes when a message is held."), on: .controls),
            item(IvyLocalizedString("DOUBLE_TAP_REACTION_TITLE", comment: "Header of the settings for reacting to a message by double-tapping it."), on: .controls),
            item(IvyLocalizedString("SWIPE_LEFT_TITLE", comment: "Header of the setting that chooses what swiping a message left does."), on: .controls),
            item(IvyLocalizedString("MESSAGE_MENU_SETTINGS_TITLE", comment: "Title of the settings that choose which message menu actions show directly."), on: .controls),
            item(IvyLocalizedString("TIPS_SHOW_AGAIN", comment: "Item in chat settings that shows the first-time tips about reactions and the message menu again."), on: .controls),
            item(IvyLocalizedString("CHAT_LIST_SEARCH_BOTTOM", comment: "Switch that moves the chat list's search and folders to the bottom, above the tab bar."), on: .startAndTabs),
            item(IvyLocalizedString("HOME_START_SECTION", comment: "Header of the setting that chooses which section the app opens with."), on: .startAndTabs),
            item(IvyLocalizedString("HOME_IMPORTANT_CHATS", comment: "Header of the chats whose unread messages Home shows as important."), on: .startAndTabs),
            item(IvyAppleSyncSettingsViewController.title, on: .calendarAndTasks),
            item(IvyWeeklyReviewViewController.title, on: .calendarAndTasks),
            IvySettingsEntry(title: IvyDetectedItemsUI.detectDatesTitle, place: chats) { $0.pushViewController(ChatsSettingsViewController(), animated: true) },
            IvySettingsEntry(title: IvyDetectedItemsUI.detectTasksTitle, place: chats) { $0.pushViewController(ChatsSettingsViewController(), animated: true) },
            IvySettingsEntry(title: IvyLocalizedString("PUSH_RELAY_TITLE", comment: "Title of the push relay settings and the item that opens them."), place: notifications) { $0.pushViewController(NotificationSettingsViewController(), animated: true) },
            IvySettingsEntry(title: IvyLocalizedString("NOTIFICATIONS_DELIVERY_TITLE", comment: "Header of the section in notification settings that explains how messages arrive."), place: notifications) { $0.pushViewController(NotificationSettingsViewController(), animated: true) },
            IvySettingsEntry(title: IvyLocalizedString("PASSCODE_TITLE", comment: "Title of the setting for Ivy's own passcode."), place: privacy) { $0.pushViewController(PrivacySettingsViewController(), animated: true) },
        ]
#if targetEnvironment(macCatalyst)
        result.append(item(IvyHotKeySettingsViewController.title, on: .controls))
#endif
        return result
    }
}

/// The results under the search field in Settings.
final class IvySettingsSearchResultsController: UITableViewController, UISearchResultsUpdating {

    private var results: [IvySettingsEntry] = []
    private lazy var entries = IvySettingsIndex.entries()
    /// Opens a result from the settings list it searched.
    var onOpen: ((IvySettingsEntry) -> Void)?

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateSearchResults(for searchController: UISearchController) {
        results = IvySettingsIndex.matches(entries, query: searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let entry = results[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = entry.title
        content.secondaryText = entry.place
        content.secondaryTextProperties.color = .Signal.secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onOpen?(results[indexPath.row])
    }
}

extension AppSettingsViewController {

    /// A search field above the settings that finds pages and Ivy's settings.
    func ivyInstallSettingsSearch() {
        let results = IvySettingsSearchResultsController()
        let searchController = UISearchController(searchResultsController: results)
        searchController.searchResultsUpdater = results
        searchController.obscuresBackgroundDuringPresentation = true
        searchController.searchBar.placeholder = IvyLocalizedString("SETTINGS_SEARCH_PLACEHOLDER", comment: "Placeholder of the search field in Settings.")
        results.onOpen = { [weak self, weak searchController] entry in
            guard let self, let navigationController else { return }
            searchController?.isActive = false
            entry.open(navigationController)
        }
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }
}
