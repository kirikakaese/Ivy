//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// What swiping a message to the left does. Swiping right stays Reply.
/// Chosen in Settings > Chats and kept on this device.
enum IvySwipeLeft: String, CaseIterable {
    case star
    case remind
    case task
    case copy
    /// Signal's own: pulls in the message's details.
    case info
    case off

    static let defaultsKey = "IvySwipeLeft"

    static func current(defaults: UserDefaults = .standard, appliesHere: Bool = IvyHand.appliesHere) -> IvySwipeLeft {
        // The Mac keeps Signal's swipe: message details.
        guard appliesHere else { return .info }
        return defaults.string(forKey: defaultsKey).flatMap(IvySwipeLeft.init(rawValue:)) ?? .star
    }

    static func set(_ action: IvySwipeLeft, defaults: UserDefaults = .standard) {
        defaults.set(action.rawValue, forKey: defaultsKey)
    }

    var title: String {
        switch self {
        case .star: IvyLocalizedString("SWIPE_LEFT_STAR", comment: "Option: swiping a message left stars it.")
        case .remind: IvyLocalizedString("SWIPE_LEFT_REMIND", comment: "Option: swiping a message left sets a reminder for it.")
        case .task: IvyLocalizedString("SWIPE_LEFT_TASK", comment: "Option: swiping a message left makes a task from it.")
        case .copy: IvyLocalizedString("SWIPE_LEFT_COPY", comment: "Option: swiping a message left copies its text.")
        case .info: IvyLocalizedString("SWIPE_LEFT_INFO", comment: "Option: swiping a message left shows its details, as Signal does.")
        case .off: IvyLocalizedString("SWIPE_LEFT_OFF", comment: "Option: swiping a message left does nothing.")
        }
    }
}

extension ConversationViewController {

    /// Runs the chosen swipe-left action on a message. Star, remind and
    /// task use the same actions as the message menu.
    func ivyPerformSwipeLeft(_ action: IvySwipeLeft, itemViewModel: CVItemViewModelImpl) {
        let interaction = itemViewModel.interaction
        let menuAction: ContextMenuAction?
        switch action {
        case .star:
            menuAction = ivyStarContextMenuAction(interaction: interaction, thread: thread)
        case .remind:
            menuAction = ivyRemindMeContextMenuAction(interaction: interaction, thread: thread)
        case .task:
            menuAction = ivyAddTaskContextMenuAction(interaction: interaction, thread: thread)
        case .copy:
            guard itemViewModel.canCopyOrShareOrSpeakText else { return }
            itemViewModel.copyTextAction()
            presentToast(text: IvyLocalizedString("SWIPE_LEFT_COPIED", comment: "Shown after swiping a message left copied its text."))
            return
        case .info, .off:
            return
        }
        guard let menuAction else { return }
        menuAction.handler(menuAction)
    }
}

extension OWSTableViewController2 {

    /// "Swipe Left": the action of swiping a message to the left.
    func ivyAddSwipeLeftSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("SWIPE_LEFT_TITLE", comment: "Header of the setting that chooses what swiping a message left does.")
        section.footerTitle = IvyLocalizedString("SWIPE_LEFT_FOOTER", comment: "Footer of the swipe-left setting.")
        for action in IvySwipeLeft.allCases {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    var content = UIListContentConfiguration.cell()
                    content.text = action.title
                    cell.contentConfiguration = content
                    let selected = IvySwipeLeft.current() == action
                    cell.accessoryType = selected ? .checkmark : .none
                    if selected {
                        cell.accessibilityTraits.insert(.selected)
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    IvySwipeLeft.set(action)
                    self?.tableView.reloadData()
                },
            ))
        }
        contents.add(section)
    }
}
