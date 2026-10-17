//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The list of open reminders: due ones first, then upcoming ones.
final class IvyRemindersViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("REMINDERS_TITLE", comment: "Title of the list of reminders.")
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = .doneButton(dismissingFrom: self)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: IvyReminderManager.remindersDidChange,
            object: nil,
        )
        updateTableContents()
    }

    private struct Row {
        let reminder: IvyReminder
        let chatName: String
        let text: String
    }

    @objc
    private func updateTableContents() {
        let reminders = IvyReminderManager.shared.openReminders()
        let rows: [Row] = SSKEnvironment.shared.databaseStorageRef.read { tx in
            reminders.map { reminder in
                let chatName = reminder.chat.thread(tx: tx).map {
                    SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx)
                } ?? IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
                return Row(reminder: reminder, chatName: chatName, text: IvyReminderManager.body(for: reminder, tx: tx))
            }
        }
        let now = Date()

        let contents = OWSTableContents(title: title)
        let due = rows.filter { $0.reminder.dueAt <= now }
        let upcoming = rows.filter { $0.reminder.dueAt > now }

        if rows.isEmpty {
            let emptySection = OWSTableSection()
            emptySection.add(.softCenterLabel(withText: IvyLocalizedString(
                "REMINDERS_EMPTY",
                comment: "Shown in the list of reminders when there are none. Explains how to add one.",
            )))
            contents.add(emptySection)
        }
        if !due.isEmpty {
            let section = OWSTableSection()
            section.headerTitle = IvyLocalizedString("REMINDERS_DUE", comment: "Header of the reminders that are due.")
            due.forEach { section.add(item(for: $0)) }
            contents.add(section)
        }
        if !upcoming.isEmpty {
            let section = OWSTableSection()
            section.headerTitle = IvyLocalizedString("REMINDERS_UPCOMING", comment: "Header of the reminders that are not due yet.")
            upcoming.forEach { section.add(item(for: $0)) }
            contents.add(section)
        }
        self.contents = contents
    }

    private func item(for row: Row) -> OWSTableItem {
        let reminder = row.reminder
        var subtitle = IvyReminderUI.dueDateText(reminder.dueAt)
        if reminder.repeats != .never {
            subtitle += " · " + IvyReminderDatePickerViewController.title(for: reminder.repeats)
        }
        return OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                var content = UIListContentConfiguration.subtitleCell()
                content.text = row.chatName
                content.secondaryText = row.text + "\n" + subtitle
                content.secondaryTextProperties.numberOfLines = 3
                content.secondaryTextProperties.color = .Signal.secondaryLabel
                content.image = UIImage(systemName: reminder.message == nil ? "bubble.left" : "text.bubble")
                cell.contentConfiguration = content
                return cell
            },
            actionBlock: {
                IvyReminderActionHandler.open(reminderId: reminder.id)
            },
            contextMenuActionProvider: { [weak self] _ in
                self?.menu(for: reminder)
            },
        )
    }

    private func menu(for reminder: IvyReminder) -> UIMenu {
        let manager = IvyReminderManager.shared
        let snoozeActions: [UIMenuElement] = IvyReminderUI.availablePresets().map { preset, date in
            UIAction(title: IvyReminderUI.title(for: preset), subtitle: IvyReminderUI.dueDateText(date)) { _ in
                manager.snooze(id: reminder.id, until: date)
            }
        } + [UIAction(title: IvyReminderUI.customTitle, image: UIImage(systemName: "calendar")) { [weak self] _ in
            let picker = IvyReminderDatePickerViewController(initialDate: reminder.dueAt) { date, repeats in
                var changed = reminder
                changed.dueAt = date
                changed.repeats = repeats
                manager.add(changed)
            }
            self?.presentFormSheet(OWSNavigationController(rootViewController: picker), animated: true)
        }]
        return UIMenu(children: [
            UIAction(
                title: IvyLocalizedString("REMINDER_DONE", comment: "Notification action that marks a reminder as done."),
                image: UIImage(systemName: "checkmark"),
            ) { _ in
                manager.markDone(id: reminder.id)
            },
            UIMenu(
                title: IvyLocalizedString("REMINDER_CHANGE_TIME", comment: "Menu that changes when a reminder is due."),
                image: UIImage(systemName: "clock"),
                children: snoozeActions,
            ),
            UIAction(
                title: IvyLocalizedString("REMINDER_DELETE", comment: "Action that deletes a reminder."),
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { _ in
                manager.delete(id: reminder.id)
            },
        ])
    }
}
