//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Turns sync with Apple Calendar and Apple Reminders on or off for this
/// device.
final class IvyAppleSyncSettingsViewController: OWSTableViewController2 {

    static var title: String {
        IvyLocalizedString("APPLE_SYNC_TITLE", comment: "Title of the settings for syncing with Apple Calendar and Apple Reminders.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Self.title
        updateTableContents()
    }

    /// Access may have changed in the system settings.
    override func appDidBecomeActive() {
        super.appDidBecomeActive()
        updateTableContents()
    }

    static func header(for kind: IvyAppleSyncKind) -> String {
        switch kind {
        case .calendar:
            return IvyLocalizedString("APPLE_SYNC_CALENDAR_HEADER", comment: "Header of the Apple Calendar sync setting.")
        case .reminders:
            return IvyLocalizedString("APPLE_SYNC_REMINDERS_HEADER", comment: "Header of the Apple Reminders sync setting.")
        }
    }

    static func footer(for kind: IvyAppleSyncKind) -> String {
        switch kind {
        case .calendar:
            return IvyLocalizedString(
                "APPLE_SYNC_CALENDAR_FOOTER",
                comment: "Explains how events sync with Apple Calendar.",
            )
        case .reminders:
            return IvyLocalizedString(
                "APPLE_SYNC_REMINDERS_FOOTER",
                comment: "Explains how tasks sync with Apple Reminders.",
            )
        }
    }

    static func title(for mode: IvyAppleSyncMode) -> String {
        switch mode {
        case .off:
            return IvyLocalizedString("APPLE_SYNC_MODE_OFF", comment: "Apple sync setting: don't sync.")
        case .copy:
            return IvyLocalizedString("APPLE_SYNC_MODE_COPY", comment: "Apple sync setting: copy Ivy's items to Apple; changes made in Apple are replaced.")
        case .twoWay:
            return IvyLocalizedString("APPLE_SYNC_MODE_TWO_WAY", comment: "Apple sync setting: changes go both ways.")
        }
    }

    static func noAccessMessage(for kind: IvyAppleSyncKind) -> String {
        switch kind {
        case .calendar:
            return IvyLocalizedString("APPLE_SYNC_NO_ACCESS_CALENDAR", comment: "Shown when Ivy has no full access to Apple Calendar.")
        case .reminders:
            return IvyLocalizedString("APPLE_SYNC_NO_ACCESS_REMINDERS", comment: "Shown when Ivy has no full access to Apple Reminders.")
        }
    }

    private func updateTableContents() {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let modes = databaseStorage.read { tx in
            Dictionary(uniqueKeysWithValues: IvyAppleSyncKind.allCases.map { ($0, IvyAppleSyncSettings.mode($0, tx: tx)) })
        }

        let contents = OWSTableContents(title: title)
        for kind in IvyAppleSyncKind.allCases {
            let current = modes[kind] ?? .off
            let section = OWSTableSection()
            section.headerTitle = Self.header(for: kind)
            section.footerTitle = Self.footer(for: kind)
            for mode in IvyAppleSyncMode.allCases {
                let isSelected = mode == current
                section.add(OWSTableItem(
                    customCellBlock: {
                        let cell = OWSTableItem.newCell()
                        var content = UIListContentConfiguration.cell()
                        content.text = Self.title(for: mode)
                        cell.contentConfiguration = content
                        cell.accessoryType = isSelected ? .checkmark : .none
                        if isSelected {
                            cell.accessibilityTraits.insert(.selected)
                        }
                        return cell
                    },
                    actionBlock: { [weak self] in
                        self?.choose(mode, for: kind, current: current)
                    },
                ))
            }
            if current != .off, !IvyAppleSyncEngine.hasAccess(kind) {
                section.add(.actionItem(
                    withText: IvyLocalizedString("APPLE_SYNC_ALLOW_ACCESS", comment: "Item that opens the system settings to allow access to Apple Calendar or Reminders."),
                    textColor: .Signal.accent,
                ) {
                    CurrentAppContext().openSystemSettings()
                })
            }
            contents.add(section)
        }

        let aboutSection = OWSTableSection()
        aboutSection.footerTitle = IvyLocalizedString(
            "APPLE_SYNC_DEVICE_FOOTER",
            comment: "Explains that Apple sync is set per device and what turning it off leaves behind.",
        )
        contents.add(aboutSection)

        self.contents = contents
    }

    private func choose(_ mode: IvyAppleSyncMode, for kind: IvyAppleSyncKind, current: IvyAppleSyncMode) {
        guard mode != current else {
            return
        }
        guard current == .off else {
            // Already agreed to leave encryption; only the direction changes.
            setMode(mode, for: kind)
            return
        }
        let sheet = ActionSheetController(
            title: IvyLocalizedString("APPLE_SYNC_CONFIRM_TITLE", comment: "Title of the confirmation before syncing with Apple Calendar or Reminders."),
            message: IvyLocalizedString(
                "APPLE_SYNC_CONFIRM_MESSAGE",
                comment: "Explains that items synced with Apple Calendar or Reminders are no longer end-to-end encrypted.",
            ),
        )
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("APPLE_SYNC_CONFIRM_ACTION", comment: "Button that turns on syncing with Apple Calendar or Reminders."),
            style: .default,
        ) { [weak self] _ in
            self?.turnOn(mode, for: kind)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }

    private func turnOn(_ mode: IvyAppleSyncMode, for kind: IvyAppleSyncKind) {
        Task { @MainActor in
            let engine = IvyAppleSyncEngine.shared
            guard await engine.requestAccess(kind) else {
                showNoAccess(kind)
                return
            }
            setMode(mode, for: kind)
        }
    }

    private func setMode(_ mode: IvyAppleSyncMode, for kind: IvyAppleSyncKind) {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            IvyAppleSyncSettings.setMode(mode, kind, tx: tx)
        }
        updateTableContents()
        IvyAppleSyncEngine.shared.scheduleSync(after: 0)
    }

    private func showNoAccess(_ kind: IvyAppleSyncKind) {
        let sheet = ActionSheetController(title: Self.header(for: kind), message: Self.noAccessMessage(for: kind))
        if let settings = AppContextUtils.openSystemSettingsAction() {
            sheet.addAction(settings)
        }
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }
}
