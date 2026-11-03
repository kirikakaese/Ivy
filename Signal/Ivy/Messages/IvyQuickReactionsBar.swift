//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// The row at the bottom of a message's reactions: tap a reaction that's
/// already there to join in, tap your own to take it back, or pick another.
/// Signal allows one reaction per person, so a new one replaces yours.
final class IvyQuickReactionsBar: UIView {

    struct Choice: Equatable {
        let emoji: String
        let isYours: Bool
    }

    /// The reactions on offer: those on the message, in their order.
    static func choices(emojis: [String], yours: String?) -> [Choice] {
        emojis.map { Choice(emoji: $0, isYours: $0 == yours) }
    }

    /// Reacts with an emoji; `isRemoving` takes your reaction back.
    var onReact: ((_ emoji: String, _ isRemoving: Bool) -> Void)?
    /// Opens the full emoji picker.
    var onPickOther: (() -> Void)?

    private let pills = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let separator = UIView()
        separator.backgroundColor = .Signal.opaqueSeparator
        let title = UILabel()
        title.text = IvyLocalizedString("REACTIONS_QUICK_TITLE", comment: "Heading of the row that adds a reaction, at the bottom of a message's reactions.").localizedUppercase
        title.font = .dynamicTypeFootnote.semibold()
        title.textColor = .Signal.secondaryLabel
        title.adjustsFontForContentSizeCategory = true

        pills.axis = .horizontal
        pills.spacing = 8
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = false
        scroll.addSubview(pills)
        pills.autoPinEdgesToSuperviewEdges()
        pills.autoMatch(.height, to: .height, of: scroll)

        let other = Self.pill(
            title: "+ " + IvyLocalizedString("REACTIONS_QUICK_OTHER", comment: "Button that opens all emoji to react with."),
            highlighted: false,
        )
        other.accessibilityLabel = IvyLocalizedString("REACTIONS_QUICK_OTHER_A11Y", comment: "Accessibility label of the button that opens all emoji to react with.")
        other.addAction(UIAction { [weak self] _ in self?.onPickOther?() }, for: .primaryActionTriggered)

        let row = UIStackView(arrangedSubviews: [scroll, other])
        row.axis = .horizontal
        row.spacing = 8
        other.setContentHuggingPriority(.required, for: .horizontal)
        other.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [separator, title, row])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(10, after: separator)
        separator.autoSetDimension(.height, toSize: 0.5)
        addSubview(stack)
        stack.autoPinEdgesToSuperviewMargins()
        row.autoSetDimension(.height, toSize: 40, relation: .greaterThanOrEqual)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(choices: [Choice]) {
        pills.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for choice in choices {
            let label = choice.isYours
                ? IvyLocalizedString("REACTIONS_QUICK_YOURS", comment: "Next to your own reaction in the row that adds a reaction; tapping it takes the reaction back.")
                : "+1"
            let button = Self.pill(title: "\(choice.emoji) \(label)", highlighted: choice.isYours)
            button.accessibilityLabel = String(
                format: choice.isYours
                    ? IvyLocalizedString("REACTIONS_QUICK_REMOVE_A11Y_FORMAT", comment: "Accessibility label that takes your reaction back. Embeds {{ emoji }}.")
                    : IvyLocalizedString("REACTIONS_QUICK_ADD_A11Y_FORMAT", comment: "Accessibility label that reacts with an emoji already on the message. Embeds {{ emoji }}."),
                choice.emoji,
            )
            button.addAction(UIAction { [weak self] _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self?.onReact?(choice.emoji, choice.isYours)
            }, for: .primaryActionTriggered)
            pills.addArrangedSubview(button)
        }
    }

    private static func pill(title: String, highlighted: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        config.baseBackgroundColor = highlighted ? UIColor.Signal.accent.withAlphaComponent(0.25) : .Signal.secondaryFill
        config.baseForegroundColor = .Signal.label
        config.background.strokeColor = highlighted ? .Signal.accent : nil
        config.background.strokeWidth = highlighted ? 1.5 : 0
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.dynamicTypeSubheadline.semibold()
            return attributes
        }
        config.title = title
        return UIButton(configuration: config)
    }
}

extension ReactionsDetailSheet {

    /// Adds or takes back the local user's reaction on this message.
    func ivyReact(emoji: String, isRemoving: Bool) {
        let messageId = self.messageId
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            ReactionManager.localUserReacted(to: messageId, emoji: emoji, isRemoving: isRemoving, tx: tx)
        }
    }
}
