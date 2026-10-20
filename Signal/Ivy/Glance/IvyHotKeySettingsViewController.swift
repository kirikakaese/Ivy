//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Chooses the Mac's system-wide shortcut for Ivy and what it does.
final class IvyHotKeySettingsViewController: OWSTableViewController2 {

    static var title: String {
        IvyLocalizedString("HOTKEY_TITLE", comment: "Title of the setting for the Mac's system-wide keyboard shortcut for Ivy.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        updateTableContents()
    }

    /// A row with a checkmark when chosen.
    private static func choice(_ text: String, isChosen: Bool, action: @escaping () -> Void) -> OWSTableItem {
        OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                var content = UIListContentConfiguration.cell()
                content.text = text
                cell.contentConfiguration = content
                cell.accessoryType = isChosen ? .checkmark : .none
                return cell
            },
            actionBlock: action,
        )
    }

    private func updateTableContents() {
        let contents = OWSTableContents(title: title)

        let keySection = OWSTableSection()
        keySection.footerTitle = IvyLocalizedString("HOTKEY_FOOTER", comment: "Explains the Mac's system-wide keyboard shortcut for Ivy.")
        for hotKey in IvyHotKey.allCases {
            keySection.add(Self.choice(hotKey.title, isChosen: IvyHotKey.current == hotKey) { [weak self] in
                IvyHotKey.current = hotKey
                IvyMenuBar.shared.applyHotKey()
                self?.updateTableContents()
            })
        }
        contents.add(keySection)

        if IvyHotKey.current != .off {
            let actionSection = OWSTableSection()
            actionSection.headerTitle = IvyLocalizedString("HOTKEY_ACTION", comment: "Header of what the Mac's system-wide shortcut does.")
            for action in IvyHotKey.Action.allCases {
                let text: String
                switch action {
                case .showIvy:
                    text = IvyLocalizedString("HOTKEY_SHOW_IVY", comment: "The system-wide shortcut brings Ivy to the front.")
                case .newMessage:
                    text = IvyLocalizedString("HOTKEY_NEW_MESSAGE", comment: "The system-wide shortcut opens a new message.")
                }
                actionSection.add(Self.choice(text, isChosen: IvyHotKey.action == action) { [weak self] in
                    IvyHotKey.action = action
                    self?.updateTableContents()
                })
            }
            contents.add(actionSection)
        }
        self.contents = contents
    }
}
