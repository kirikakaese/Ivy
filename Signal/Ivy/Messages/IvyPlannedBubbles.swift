//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// The chat's scheduled messages, shown above the message field like
/// outgoing bubbles with a dashed outline and the time they are sent.
/// Clicking one offers Send Now, Change Time and Delete.
@MainActor
final class IvyPlannedMessagesView: UIView {

    /// Bubbles shown at most; the rest are behind "more".
    static let maxBubbles = 3

    private let chat: IvyChatReference?
    private weak var presenter: UIViewController?
    private let onHeightChange: () -> Void
    private let stack = UIStackView()
    private var shownIds = [String]()
    /// The first load happens while the chat lays out its bottom bar.
    private var isLoaded = false

    init(thread: TSThread, presenter: UIViewController, onHeightChange: @escaping () -> Void) {
        self.chat = IvyChatReference(thread: thread)
        self.presenter = presenter
        self.onHeightChange = onHeightChange
        super.init(frame: .zero)

        stack.axis = .vertical
        stack.alignment = .trailing
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: IvyScheduledSender.scheduledDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: UIApplication.significantTimeChangeNotification, object: nil)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func reload() {
        let messages = chat.map { IvyScheduledUI.pending(in: $0) } ?? []
        let ids = messages.map { "\($0.id)@\($0.sendAt.timeIntervalSince1970)@\($0.previewText.hashValue)" }
        guard !isLoaded || ids != shownIds else {
            return
        }
        let hadBubbles = !shownIds.isEmpty
        shownIds = ids

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.directionalLayoutMargins = messages.isEmpty
            ? .zero
            : NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
        for message in messages.prefix(Self.maxBubbles) {
            stack.addArrangedSubview(bubble(for: message))
        }
        if messages.count > Self.maxBubbles, let chat {
            var configuration = UIButton.Configuration.plain()
            configuration.title = String(
                format: IvyLocalizedString("SCHEDULED_BUBBLES_MORE_FORMAT", comment: "Below the scheduled message bubbles in a chat: how many more there are. Embeds {{ number }}."),
                (messages.count - Self.maxBubbles).formatted(),
            )
            configuration.buttonSize = .small
            configuration.baseForegroundColor = .Signal.accent
            stack.addArrangedSubview(UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.presenter?.presentFormSheet(
                    OWSNavigationController(rootViewController: IvyScheduledMessagesViewController(chat: chat)),
                    animated: true,
                )
            }))
        }
        if isLoaded, hadBubbles || !messages.isEmpty {
            onHeightChange()
        }
        isLoaded = true
    }

    private func bubble(for message: IvyScheduledMessage) -> UIView {
        let bubble = IvyDashedBubble()
        bubble.textLabel.text = message.previewText
        bubble.timeLabel.text = String(
            format: IvyLocalizedString("SCHEDULED_BUBBLE_TIME_FORMAT", comment: "Under a scheduled message bubble in a chat: when it is sent. Embeds {{ date and time }}."),
            IvyScheduledUI.sendTimeText(message.sendAt),
        )
        bubble.accessibilityLabel = (bubble.textLabel.text ?? "") + ", " + (bubble.timeLabel.text ?? "")
        if let presenter {
            bubble.menu = UIMenu(children: IvyScheduledUI.menuActions(for: message, from: presenter))
        }
        bubble.showsMenuAsPrimaryAction = true
        bubble.widthAnchor.constraint(lessThanOrEqualTo: stack.layoutMarginsGuide.widthAnchor, multiplier: 0.8).isActive = true
        return bubble
    }
}

/// An outgoing bubble that isn't sent yet: a dashed outline, the text and
/// the send time.
private final class IvyDashedBubble: UIButton {

    let textLabel = UILabel()
    let timeLabel = UILabel()
    private let outline = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        textLabel.font = .dynamicTypeBody
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.textColor = .Signal.label
        textLabel.numberOfLines = 4

        let clock = UIImageView(image: UIImage(systemName: "clock"))
        clock.tintColor = .Signal.accent
        clock.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1)
        clock.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.font = .dynamicTypeCaption1
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = .Signal.accent
        let timeRow = UIStackView(arrangedSubviews: [clock, timeLabel])
        timeRow.spacing = 4
        timeRow.alignment = .center

        let content = UIStackView(arrangedSubviews: [textLabel, timeRow])
        content.axis = .vertical
        content.spacing = 4
        content.alignment = .trailing
        content.isUserInteractionEnabled = false
        addSubview(content)
        content.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))

        outline.fillColor = UIColor.clear.cgColor
        outline.lineWidth = 1.5
        outline.lineDashPattern = [6, 4]
        layer.addSublayer(outline)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outline.frame = bounds
        outline.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 18).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private func updateColors() {
        outline.strokeColor = UIColor.Signal.accent.resolvedColor(with: traitCollection).cgColor
        backgroundColor = UIColor.Signal.accent.withAlphaComponent(0.08)
        layer.cornerRadius = 18
    }
}
