//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Snoozing chats from the chat list, and the list of snoozed chats.
enum IvySnoozeUI {

    static var snoozeTitle: String {
        IvyLocalizedString("SNOOZE_CHAT", comment: "Context menu action that hides a chat until a chosen time.")
    }

    static var snoozedChatsTitle: String {
        IvyLocalizedString("SNOOZED_CHATS_TITLE", comment: "Title of the list of snoozed chats.")
    }

    static func untilText(_ date: Date) -> String {
        String(
            format: IvyLocalizedString("SNOOZED_UNTIL_FORMAT", comment: "When a snoozed chat comes back. Embeds {{ date and time }}."),
            IvyReminderUI.dueDateText(date),
        )
    }

    /// Later today, tonight, tomorrow and next week.
    static let presets: [IvyReminder.Preset] = [.laterToday, .tonight, .tomorrowMorning, .nextWeek]

    /// The "Snooze" menu for a chat's context menu.
    static func menu(chat: IvyChatReference, from viewController: UIViewController) -> UIMenu {
        let now = Date()
        var children: [UIMenuElement] = presets.compactMap { preset in
            preset.dueDate(from: now).map { date in
                UIAction(title: IvyReminderUI.title(for: preset), subtitle: IvyReminderUI.dueDateText(date)) { _ in
                    snooze(chat, until: date)
                }
            }
        }
        children.append(UIAction(title: IvyReminderUI.customTitle, image: UIImage(systemName: "calendar")) { [weak viewController] _ in
            let picker = IvyReminderDatePickerViewController(title: snoozeTitle, showsRepeat: false) { date, _ in
                snooze(chat, until: date)
            }
            viewController?.presentFormSheet(OWSNavigationController(rootViewController: picker), animated: true)
        })
        return UIMenu(title: snoozeTitle, image: UIImage(systemName: "moon.zzz"), children: children)
    }

    static func snooze(_ chat: IvyChatReference, until date: Date) {
        guard date > Date() else {
            return
        }
        IvySnoozedChats.shared.snooze(chat, until: date)
        IvySnoozedChats.shared.refresh()
        CurrentAppContext().frontmostViewController()?.presentToast(text: untilText(date))
    }
}

// MARK: - Chat list

extension ChatListViewController {

    /// "Snoozed Chats" for the profile menu, when any are snoozed.
    func ivySnoozeMenuActions() -> [UIAction] {
        guard !IvySnoozedChats.shared.activeSnoozes().isEmpty else {
            return []
        }
        return [UIAction(title: IvySnoozeUI.snoozedChatsTitle, image: UIImage(systemName: "moon.zzz")) { [weak self] _ in
            self?.presentFormSheet(OWSNavigationController(rootViewController: IvySnoozedChatsViewController()), animated: true)
        }]
    }
}

// MARK: - Snoozed chats

/// The snoozed chats, soonest back first. Tapping one opens it or wakes it.
final class IvySnoozedChatsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvySnoozeUI.snoozedChatsTitle
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.dismiss(animated: true)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateTableContents),
            name: IvyDataStore.dataDidChange,
            object: nil,
        )
        updateTableContents()
    }

    @objc
    private func updateTableContents() {
        let snoozes = IvySnoozedChats.shared.activeSnoozes()
        let section = OWSTableSection()
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            for snooze in snoozes {
                guard let thread = snooze.chat.thread(tx: tx) else {
                    continue
                }
                let name = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                let threadId = thread.uniqueId
                section.add(.disclosureItem(withText: name, subtitle: IvySnoozeUI.untilText(snooze.until)) { [weak self] in
                    self?.showActions(chat: snooze.chat, name: name, threadId: threadId)
                })
            }
        }
        if snoozes.isEmpty {
            section.add(.label(
                withText: IvyLocalizedString("SNOOZED_CHATS_EMPTY", comment: "Shown in the list of snoozed chats when there are none."),
                accessoryType: .none,
            ))
        }
        let contents = OWSTableContents(title: title)
        contents.add(section)
        self.contents = contents
    }

    private func showActions(chat: IvyChatReference, name: String, threadId: String) {
        let sheet = ActionSheetController(title: name)
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("SNOOZE_OPEN_CHAT", comment: "Action that opens a snoozed chat without waking it."),
        ) { [weak self] _ in
            self?.dismiss(animated: true) {
                SignalApp.shared.presentConversationForThread(threadUniqueId: threadId, animated: true)
            }
        })
        sheet.addAction(ActionSheetAction(
            title: IvyLocalizedString("SNOOZE_WAKE", comment: "Action that ends a chat's snooze so it shows in the chat list again."),
        ) { _ in
            IvySnoozedChats.shared.unsnooze(chat)
        })
        sheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(sheet)
    }
}
