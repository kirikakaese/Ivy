//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// Double-tapping a message reacts with a chosen emoji; double-tapping again
/// takes the reaction back. Chosen in Settings > Chats and kept on this
/// device. Your own messages that can still be edited keep Signal's
/// double-tap to edit.
enum IvyDoubleTapReaction {

    static let enabledKey = "IvyDoubleTapReactionEnabled"
    static let emojiKey = "IvyDoubleTapReactionEmoji"
    static let defaultEmoji = "❤️"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func emoji(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: emojiKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultEmoji
    }

    static func setEmoji(_ emoji: String, defaults: UserDefaults = .standard) {
        defaults.set(emoji, forKey: emojiKey)
    }

    /// What a double tap does: react with the emoji, or take it back when
    /// it's already your reaction.
    static func action(emoji: String, yourReaction: String?) -> (emoji: String, isRemoving: Bool) {
        if let yourReaction, yourReaction == emoji {
            return (yourReaction, true)
        }
        return (emoji, false)
    }
}

extension ConversationViewController {

    /// Reacts to the double-tapped message, if double-tap reactions are on
    /// and the chat allows reacting. Returns whether it did.
    func ivyHandleDoubleTapReaction(cell: CVCell, sender: UIGestureRecognizer) -> Bool {
        guard
            IvyDoubleTapReaction.isEnabled(),
            let renderItem = cell.renderItem,
            let message = renderItem.interaction as? TSMessage,
            thread.canSendReactionToThread,
            shouldShowReactionPickerForInteraction(message)
        else {
            return false
        }
        let (emoji, isRemoving) = IvyDoubleTapReaction.action(
            emoji: IvyDoubleTapReaction.emoji(),
            yourReaction: renderItem.reactionState?.localUserEmojiVariant,
        )
        let messageId = message.uniqueId
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            ReactionManager.localUserReacted(to: messageId, emoji: emoji, isRemoving: isRemoving, tx: tx)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !isRemoving, !UIAccessibility.isReduceMotionEnabled {
            ivyPopEmoji(emoji, at: sender.location(in: view))
        }
        return true
    }

    /// The emoji grows out of the tap and fades away.
    private func ivyPopEmoji(_ emoji: String, at point: CGPoint) {
        let label = UILabel()
        label.text = emoji
        label.font = .systemFont(ofSize: 56)
        label.sizeToFit()
        label.center = point
        label.isUserInteractionEnabled = false
        label.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        label.alpha = 0
        view.addSubview(label)
        UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
            label.transform = .identity
            label.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0.25) {
                label.transform = CGAffineTransform(translationX: 0, y: -24).scaledBy(x: 0.8, y: 0.8)
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
}

extension ChatsSettingsViewController {

    /// "Double-Tap": react with an emoji by double-tapping a message.
    func ivyAddDoubleTapSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.headerTitle = IvyLocalizedString("DOUBLE_TAP_REACTION_TITLE", comment: "Header of the settings for reacting to a message by double-tapping it.")
        section.footerTitle = IvyLocalizedString("DOUBLE_TAP_REACTION_FOOTER", comment: "Footer explaining double-tap reactions.")
        section.add(.switch(
            withText: IvyLocalizedString("DOUBLE_TAP_REACTION_SWITCH", comment: "Switch that turns reacting by double-tapping a message on or off."),
            isOn: { IvyDoubleTapReaction.isEnabled() },
            actionBlock: { [weak self] uiSwitch in
                IvyDoubleTapReaction.setEnabled(uiSwitch.isOn)
                self?.tableView.reloadData()
            },
        ))
        section.add(OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                var content = UIListContentConfiguration.valueCell()
                content.text = IvyLocalizedString("DOUBLE_TAP_REACTION_EMOJI", comment: "Item that chooses the emoji a double tap reacts with.")
                content.secondaryText = IvyDoubleTapReaction.emoji()
                if !IvyDoubleTapReaction.isEnabled() {
                    content.textProperties.color = .Signal.tertiaryLabel
                }
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                return cell
            },
            actionBlock: { [weak self] in
                guard IvyDoubleTapReaction.isEnabled() else { return }
                let picker = EmojiPickerSheet(message: nil, allowReactionConfiguration: false) { [weak self] emoji in
                    guard let emoji else { return }
                    IvyDoubleTapReaction.setEmoji(emoji.rawValue)
                    self?.tableView.reloadData()
                }
                self?.present(picker, animated: true)
            },
        ))
        contents.add(section)
    }
}
