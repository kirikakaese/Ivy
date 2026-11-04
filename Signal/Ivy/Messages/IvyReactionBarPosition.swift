//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Which hand Ivy is used with: it decides the side of things that sit at
/// the edge, like the reaction bar beside the menu and the scroll buttons
/// in a chat. Chosen in Settings > Chats and kept on this device.
enum IvyHand: String, CaseIterable {
    case right
    case left

    static let defaultsKey = "IvyHand"

    static func current(defaults: UserDefaults = .standard) -> IvyHand {
        if let saved = defaults.string(forKey: defaultsKey).flatMap(IvyHand.init(rawValue:)) {
            return saved
        }
        // Before there was a hand setting, the bar's side was chosen directly.
        return defaults.string(forKey: IvyReactionBarPosition.defaultsKey) == IvyReactionBarPosition.left.rawValue ? .left : .right
    }

    static func set(_ hand: IvyHand, defaults: UserDefaults = .standard) {
        defaults.set(hand.rawValue, forKey: defaultsKey)
    }

    var title: String {
        switch self {
        case .right: IvyLocalizedString("HAND_RIGHT", comment: "Option for using Ivy with the right hand.")
        case .left: IvyLocalizedString("HAND_LEFT", comment: "Option for using Ivy with the left hand.")
        }
    }
}

/// Where the reaction bar goes when a message is held: at the bottom of the
/// screen, or upright beside the actions on the side of the chosen hand.
/// Chosen in Settings > Chats and kept on this device.
enum IvyReactionBarPosition: String, CaseIterable {
    case bottom
    case right
    case left

    static let defaultsKey = "IvyReactionBarPosition"

    /// Whether the bar goes beside the menu (true) or at the bottom.
    static func isBesideMenu(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: defaultsKey) != IvyReactionBarPosition.bottom.rawValue
    }

    static func setBesideMenu(_ beside: Bool, defaults: UserDefaults = .standard) {
        defaults.set(beside ? IvyReactionBarPosition.right.rawValue : IvyReactionBarPosition.bottom.rawValue, forKey: defaultsKey)
    }

    static func current(defaults: UserDefaults = .standard) -> IvyReactionBarPosition {
        guard isBesideMenu(defaults: defaults) else { return .bottom }
        return IvyHand.current(defaults: defaults) == .left ? .left : .right
    }

    /// The placement for a context menu opening now. In landscape on iPhone
    /// the actions sit beside the message, so the bar keeps Signal's place
    /// above it.
    static func placementForContextMenu(isLandscapePhone: Bool = IvyReactionBarPosition.isLandscapePhone) -> IvyReactionBarPosition? {
        isLandscapePhone ? nil : current()
    }

    static var isLandscapePhone: Bool {
        let size = CurrentAppContext().frame.size
        return !UIDevice.current.isIPad && size.width > size.height
    }

    /// For an upright bar, which side it's on: 1 right, -1 left.
    var verticalSide: CGFloat? {
        switch self {
        case .bottom: nil
        case .right: 1
        case .left: -1
        }
    }
}

extension ChatsSettingsViewController {

    /// "Hand": which side edge controls go to.
    func ivyAddHandSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("HAND_TITLE", comment: "Header of the setting that chooses which hand Ivy is used with.")
        section.footerTitle = IvyLocalizedString("HAND_FOOTER", comment: "Footer explaining what the hand setting moves.")
        for hand in IvyHand.allCases {
            section.add(Self.ivyCheckmarkItem(title: hand.title, isSelected: { IvyHand.current() == hand }) { [weak self] in
                IvyHand.set(hand)
                self?.tableView.reloadData()
            })
        }
        contents.add(section)
    }

    /// "Reaction bar": where it goes when a message is held.
    func ivyAddReactionBarSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("REACTION_BAR_POSITION_TITLE", comment: "Header of the setting that chooses where the reaction bar goes when a message is held.")
        section.footerTitle = IvyLocalizedString("REACTION_BAR_POSITION_FOOTER", comment: "Footer explaining the reaction bar position setting.")
        let options: [(title: String, beside: Bool)] = [
            (IvyLocalizedString("REACTION_BAR_POSITION_BESIDE", comment: "Option that puts the reaction bar upright beside the message's actions, on the side of the chosen hand."), true),
            (IvyLocalizedString("REACTION_BAR_POSITION_BOTTOM", comment: "Option that puts the reaction bar at the bottom of the screen."), false),
        ]
        for option in options {
            section.add(Self.ivyCheckmarkItem(title: option.title, isSelected: { IvyReactionBarPosition.isBesideMenu() == option.beside }) { [weak self] in
                IvyReactionBarPosition.setBesideMenu(option.beside)
                self?.tableView.reloadData()
            })
        }
        contents.add(section)
    }

    private static func ivyCheckmarkItem(title: String, isSelected: @escaping () -> Bool, action: @escaping () -> Void) -> OWSTableItem {
        OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                var content = UIListContentConfiguration.cell()
                content.text = title
                cell.contentConfiguration = content
                let selected = isSelected()
                cell.accessoryType = selected ? .checkmark : .none
                if selected {
                    cell.accessibilityTraits.insert(.selected)
                }
                return cell
            },
            actionBlock: action,
        )
    }
}
