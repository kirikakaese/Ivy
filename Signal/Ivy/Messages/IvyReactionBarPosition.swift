//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Where the reaction bar goes when a message is held: at the bottom of the
/// screen, or upright beside the actions on the right or the left. Chosen in
/// Settings > Chats and kept on this device.
enum IvyReactionBarPosition: String, CaseIterable {
    case bottom
    case right
    case left

    static let defaultsKey = "IvyReactionBarPosition"
    static let `default`: IvyReactionBarPosition = .right

    static func current(defaults: UserDefaults = .standard) -> IvyReactionBarPosition {
        defaults.string(forKey: defaultsKey).flatMap(IvyReactionBarPosition.init(rawValue:)) ?? .default
    }

    static func set(_ position: IvyReactionBarPosition, defaults: UserDefaults = .standard) {
        defaults.set(position.rawValue, forKey: defaultsKey)
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

    var title: String {
        switch self {
        case .bottom:
            IvyLocalizedString("REACTION_BAR_POSITION_BOTTOM", comment: "Option that puts the reaction bar at the bottom of the screen.")
        case .right:
            IvyLocalizedString("REACTION_BAR_POSITION_RIGHT", comment: "Option that puts the reaction bar upright to the right of the message's actions.")
        case .left:
            IvyLocalizedString("REACTION_BAR_POSITION_LEFT", comment: "Option that puts the reaction bar upright to the left of the message's actions.")
        }
    }
}

extension ChatsSettingsViewController {

    /// "Reaction bar": where it goes when a message is held.
    func ivyAddReactionBarSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("REACTION_BAR_POSITION_TITLE", comment: "Header of the setting that chooses where the reaction bar goes when a message is held.")
        section.footerTitle = IvyLocalizedString("REACTION_BAR_POSITION_FOOTER", comment: "Footer explaining the reaction bar position setting.")
        for position in IvyReactionBarPosition.allCases {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    var content = UIListContentConfiguration.cell()
                    content.text = position.title
                    cell.contentConfiguration = content
                    let isSelected = IvyReactionBarPosition.current() == position
                    cell.accessoryType = isSelected ? .checkmark : .none
                    if isSelected {
                        cell.accessibilityTraits.insert(.selected)
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    IvyReactionBarPosition.set(position)
                    self?.tableView.reloadData()
                },
            ))
        }
        contents.add(section)
    }
}
