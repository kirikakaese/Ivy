//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Which section the app opens with, and which chats Home treats as
/// important.
final class IvyHomeSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("HOME_SETTINGS_TITLE", comment: "Title of the settings for Home and navigation.")
        updateTableContents()
    }

    static func title(for section: IvySection) -> String {
        switch section {
        case .home:
            return IvyLocalizedString("HOME_TITLE", comment: "Title of the Home section with today's agenda, tasks and important messages.")
        case .chats:
            return HomeTabBarController.Tabs.chatList.title
        case .calendar:
            return IvyCalendarUI.calendarTitle
        case .calls:
            return HomeTabBarController.Tabs.calls.title
        }
    }

    private func updateTableContents() {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let (startSection, importantChats) = databaseStorage.read { tx in
            (IvyHomeSettings.startSection(tx: tx), IvyHomeSettings.importantChats(tx: tx))
        }

        let contents = OWSTableContents(title: title)

        let startSectionSection = OWSTableSection()
        startSectionSection.headerTitle = IvyLocalizedString("HOME_START_SECTION", comment: "Header of the setting that chooses which section the app opens with.")
        startSectionSection.footerTitle = IvyLocalizedString("HOME_START_SECTION_FOOTER", comment: "Explains when the start section setting applies.")
        for section in IvySection.allCases {
            let isSelected = section == startSection
            startSectionSection.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    var content = UIListContentConfiguration.cell()
                    content.text = Self.title(for: section)
                    cell.contentConfiguration = content
                    cell.accessoryType = isSelected ? .checkmark : .none
                    if isSelected {
                        cell.accessibilityTraits.insert(.selected)
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    databaseStorage.write { tx in IvyHomeSettings.setStartSection(section, tx: tx) }
                    self?.updateTableContents()
                },
            ))
        }
        contents.add(startSectionSection)

        let importantSection = OWSTableSection()
        importantSection.headerTitle = IvyLocalizedString("HOME_IMPORTANT_CHATS", comment: "Header of the chats whose unread messages Home shows as important.")
        importantSection.footerTitle = IvyLocalizedString(
            "HOME_IMPORTANT_CHATS_FOOTER",
            comment: "Explains which messages Home shows as important.",
        )
        let names: [IvyChatReference: String] = databaseStorage.read { tx in
            var names = [IvyChatReference: String]()
            for chat in importantChats {
                if let thread = chat.thread(tx: tx) {
                    names[chat] = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                }
            }
            return names
        }
        for chat in importantChats {
            guard let name = names[chat] else { continue }
            importantSection.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    var content = UIListContentConfiguration.cell()
                    content.text = name
                    content.image = UIImage(systemName: "star.fill")
                    content.imageProperties.tintColor = .Signal.accent
                    cell.contentConfiguration = content
                    return cell
                },
                contextMenuActionProvider: { [weak self] _ in
                    UIMenu(children: [UIAction(
                        title: IvyLocalizedString("HOME_IMPORTANT_CHAT_REMOVE", comment: "Action that removes a chat from the important chats."),
                        image: UIImage(systemName: "star.slash"),
                        attributes: .destructive,
                    ) { _ in
                        self?.setImportantChats(importantChats.filter { $0 != chat })
                    }])
                },
            ))
        }
        importantSection.add(.actionItem(
            withText: IvyLocalizedString("HOME_IMPORTANT_CHAT_ADD", comment: "Button that adds a chat to the important chats."),
            textColor: .Signal.accent,
        ) { [weak self] in
            let chooser = IvyChatChooserViewController(preferredChat: nil) { thread in
                guard let chat = IvyChatReference(thread: thread), !importantChats.contains(chat) else { return }
                self?.setImportantChats(importantChats + [chat])
            }
            chooser.title = IvyLocalizedString("HOME_IMPORTANT_CHAT_ADD", comment: "Button that adds a chat to the important chats.")
            self?.presentFormSheet(OWSNavigationController(rootViewController: chooser), animated: true)
        })
        contents.add(importantSection)

        self.contents = contents
    }

    private func setImportantChats(_ chats: [IvyChatReference]) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in IvyHomeSettings.setImportantChats(chats, tx: tx) }
        updateTableContents()
    }
}
