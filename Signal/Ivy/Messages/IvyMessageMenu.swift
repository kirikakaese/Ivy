//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// The actions of a message's menu, as Ivy arranges them.
enum IvyMessageMenuItem: String, CaseIterable {
    // The icon row on top.
    case reply, copy, forward, select
    // Rows, shown directly or under "More" as chosen in Settings.
    case edit, info, pin, star, speak, share, save, transcribe, voiceTask, remind, task, calendar
    // Actions that only some messages have (polls, payments, shared plans); always shown.
    case other
    case delete

    static let iconRow: [IvyMessageMenuItem] = [.reply, .copy, .forward, .select]

    /// The rows that can go under "More", in the order Settings lists them.
    static let configurable: [IvyMessageMenuItem] = [.info, .star, .pin, .edit, .share, .save, .speak, .transcribe, .voiceTask, .remind, .task, .calendar]

    static let underMoreByDefault: Set<IvyMessageMenuItem> = [.speak, .transcribe, .voiceTask, .remind, .task, .calendar]

    var title: String {
        switch self {
        case .info: IvyLocalizedString("MESSAGE_MENU_ITEM_INFO", comment: "Message menu action in the list of actions that can go under More: details of the message.")
        case .star: IvyLocalizedString("MESSAGE_MENU_ITEM_STAR", comment: "Message menu action in the list of actions that can go under More: star the message.")
        case .pin: IvyLocalizedString("MESSAGE_MENU_ITEM_PIN", comment: "Message menu action in the list of actions that can go under More: pin the message in the chat.")
        case .edit: IvyLocalizedString("MESSAGE_MENU_ITEM_EDIT", comment: "Message menu action in the list of actions that can go under More: edit your message.")
        case .share: IvyLocalizedString("MESSAGE_MENU_ITEM_SHARE", comment: "Message menu action in the list of actions that can go under More: share an attachment.")
        case .save: IvyLocalizedString("MESSAGE_MENU_ITEM_SAVE", comment: "Message menu action in the list of actions that can go under More: save an attachment.")
        case .speak: IvyLocalizedString("MESSAGE_MENU_ITEM_SPEAK", comment: "Message menu action in the list of actions that can go under More: read the message aloud.")
        case .transcribe: IvyLocalizedString("MESSAGE_MENU_ITEM_TRANSCRIBE", comment: "Message menu action in the list of actions that can go under More: transcribe a voice message.")
        case .voiceTask: IvyLocalizedString("MESSAGE_MENU_ITEM_VOICE_TASK", comment: "Message menu action in the list of actions that can go under More: make a task from a voice message.")
        case .remind: IvyLocalizedString("MESSAGE_MENU_ITEM_REMIND", comment: "Message menu action in the list of actions that can go under More: remind me about the message.")
        case .task: IvyLocalizedString("MESSAGE_MENU_ITEM_TASK", comment: "Message menu action in the list of actions that can go under More: add a task.")
        case .calendar: IvyLocalizedString("MESSAGE_MENU_ITEM_CALENDAR", comment: "Message menu action in the list of actions that can go under More: add to the calendar.")
        case .reply, .copy, .forward, .select, .other, .delete: rawValue
        }
    }

    init(_ type: MessageAction.MessageActionType) {
        switch type {
        case .reply: self = .reply
        case .copy: self = .copy
        case .forward: self = .forward
        case .select: self = .select
        case .info: self = .info
        case .delete: self = .delete
        case .share: self = .share
        case .save: self = .save
        case .speak, .stopSpeaking: self = .speak
        case .edit: self = .edit
        case .pin, .unpin: self = .pin
        case .endPoll, .showPaymentDetails: self = .other
        }
    }
}

enum IvyMessageMenu {

    static let underMoreKey = "IvyMessageMenuUnderMore"

    static func underMore(defaults: UserDefaults = .standard) -> Set<IvyMessageMenuItem> {
        guard let saved = defaults.stringArray(forKey: underMoreKey) else {
            return IvyMessageMenuItem.underMoreByDefault
        }
        return Set(saved.compactMap(IvyMessageMenuItem.init(rawValue:)))
    }

    static func setShownDirectly(_ item: IvyMessageMenuItem, _ shown: Bool, defaults: UserDefaults = .standard) {
        var items = underMore(defaults: defaults)
        if shown { items.remove(item) } else { items.insert(item) }
        defaults.set(items.map(\.rawValue).sorted(), forKey: underMoreKey)
    }

    struct Plan: Equatable {
        /// Indices into the actions, in the order they show.
        var icons: [Int]
        var rows: [Int]
        var more: [Int]
        var delete: [Int]
    }

    /// Splits a message's actions into the icon row, the rows, those under
    /// "More" and Delete. An icon row needs at least two actions; "More" is
    /// only worth it for two or more.
    static func plan(items: [IvyMessageMenuItem], underMore: Set<IvyMessageMenuItem>) -> Plan {
        var icons = IvyMessageMenuItem.iconRow.compactMap { item in items.firstIndex(of: item) }
        if icons.count < 2 { icons = [] }
        let rest = items.indices.filter { !icons.contains($0) }
        let delete = rest.filter { items[$0] == .delete }
        var more = rest.filter { underMore.contains(items[$0]) }
        if more.count < 2 { more = [] }
        let rows = rest.filter { !delete.contains($0) && !more.contains($0) }
        return Plan(icons: icons, rows: rows, more: more, delete: delete)
    }

    /// The menu as Ivy shows it.
    static func arrange(_ actions: [ContextMenuAction]) -> ContextMenu {
        let plan = plan(items: actions.map { $0.ivyItem ?? .other }, underMore: underMore())
        var children = plan.rows.map { actions[$0] }
        if !plan.more.isEmpty {
            let more = ContextMenuAction(
                title: IvyLocalizedString("MESSAGE_MENU_MORE", comment: "Message menu row that opens the less used actions."),
                image: UIImage(systemName: "ellipsis.circle"),
                handler: { _ in },
            )
            more.ivySubmenu = plan.more.map { actions[$0] }
            children.append(more)
        }
        children += plan.delete.map { actions[$0] }
        let menu = ContextMenu(children)
        menu.ivyIconRow = plan.icons.map { actions[$0] }
        return menu
    }
}

/// Settings > Chats > Message Menu: which actions show directly and which
/// sit under "More".
final class IvyMessageMenuSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = IvyLocalizedString("MESSAGE_MENU_SETTINGS_TITLE", comment: "Title of the settings that choose which message menu actions show directly.")
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("MESSAGE_MENU_SETTINGS_HEADER", comment: "Header above the switches that show message menu actions directly.")
        section.footerTitle = IvyLocalizedString("MESSAGE_MENU_SETTINGS_FOOTER", comment: "Footer explaining which message menu actions are always there and where the others go.")
        for item in IvyMessageMenuItem.configurable {
            section.add(.switch(
                withText: item.title,
                isOn: { !IvyMessageMenu.underMore().contains(item) },
                actionBlock: { uiSwitch in
                    IvyMessageMenu.setShownDirectly(item, uiSwitch.isOn)
                },
            ))
        }
        contents.add(section)
        self.contents = contents
    }
}

extension ChatsSettingsViewController {

    /// "Message Menu": opens the choice of actions shown directly.
    func ivyAddMessageMenuSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.add(.disclosureItem(
            withText: IvyLocalizedString("MESSAGE_MENU_SETTINGS_TITLE", comment: "Title of the settings that choose which message menu actions show directly."),
            actionBlock: { [weak self] in
                self?.navigationController?.pushViewController(IvyMessageMenuSettingsViewController(), animated: true)
            },
        ))
        contents.add(section)
    }
}
