//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// First-time explanations of the reaction bar, double-tap and the shorter
/// message menu: a welcome sheet after the first message menu closes, a tip
/// beside the reaction bar the first few times, and a hint in the reactions
/// sheet. Each is remembered on this device; Settings > Chats shows them
/// again.
enum IvyFirstTimeTips {

    static let welcomeKey = "IvyTipReactionsWelcomeShown"
    static let barTipKey = "IvyTipReactionBarCount"
    static let sheetHintKey = "IvyTipReactionsSheetShown"
    /// How often the tip beside the bar appears, unless closed sooner.
    static let barTipTimes = 3

    static func reset(defaults: UserDefaults = .standard) {
        [welcomeKey, barTipKey, sheetHintKey].forEach { defaults.removeObject(forKey: $0) }
    }

    static func isWelcomeDue(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: welcomeKey)
    }

    static func markWelcomeShown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: welcomeKey)
    }

    /// True for the first few menus with a reaction bar.
    static func takeBarTip(defaults: UserDefaults = .standard) -> Bool {
        let count = defaults.integer(forKey: barTipKey)
        guard count < barTipTimes else { return false }
        defaults.set(count + 1, forKey: barTipKey)
        return true
    }

    /// Closing the tip ends it for good.
    static func closeBarTip(defaults: UserDefaults = .standard) {
        defaults.set(barTipTimes, forKey: barTipKey)
    }

    /// True once: the hint in the reactions sheet is due.
    static func takeSheetHint(defaults: UserDefaults = .standard) -> Bool {
        take(flag: sheetHintKey, defaults: defaults)
    }

    private static func take(flag: String, defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: flag) else { return false }
        defaults.set(true, forKey: flag)
        return true
    }

    // MARK: - A: welcome sheet

    @MainActor
    static func welcomeSheet(openSettings: @escaping () -> Void) -> HeroSheetViewController {
        typealias Body = HeroSheetViewController.Body
        let image = { (name: String) in UIImage(systemName: name) ?? UIImage() }
        return HeroSheetViewController(
            hero: .circleIcon(
                icon: image("hand.wave.fill"),
                iconSize: 36,
                tintColor: .white,
                backgroundColor: .Signal.accent,
            ),
            title: IvyLocalizedString("TIPS_WELCOME_TITLE", comment: "Title of the sheet that explains the reaction bar, double-tap and the shorter message menu the first time."),
            body: Body([
                .bullets([
                    Body.BulletPoint(icon: image("arrow.left.and.right"), text: IvyLocalizedString("TIPS_WELCOME_BAR", comment: "Point in the first-time sheet: the reaction bar can sit right, left or at the bottom.")),
                    Body.BulletPoint(icon: image("heart"), text: IvyLocalizedString("TIPS_WELCOME_DOUBLE_TAP", comment: "Point in the first-time sheet: double-tapping a message reacts.")),
                    Body.BulletPoint(icon: image("ellipsis.circle"), text: IvyLocalizedString("TIPS_WELCOME_MENU", comment: "Point in the first-time sheet: less used actions are under More, and which ones show can be chosen.")),
                ]),
            ]),
            primary: .button(.dismissing(title: IvyLocalizedString("TIPS_GOT_IT", comment: "Button that closes a first-time explanation."))),
            secondary: .button(HeroSheetViewController.Button(
                title: IvyLocalizedString("TIPS_CUSTOMIZE", comment: "Button in the first-time sheet that opens the chat settings."),
                style: .secondary,
                action: .custom { sheet in
                    sheet.dismiss(animated: true, completion: openSettings)
                },
            )),
        )
    }
}

extension ConversationViewController {

    /// Shows the welcome sheet once, after the first message menu closed.
    /// Waits while an action from the menu shows something else, so the
    /// sheet comes the next time instead.
    func ivyShowReactionsWelcomeIfDue() {
        guard IvyFirstTimeTips.isWelcomeDue() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, presentedViewController == nil, view.window != nil, IvyFirstTimeTips.isWelcomeDue() else { return }
            IvyFirstTimeTips.markWelcomeShown()
            let sheet = IvyFirstTimeTips.welcomeSheet { [weak self] in
                let settings = ChatsSettingsViewController()
                let navigation = OWSNavigationController(rootViewController: settings)
                settings.navigationItem.leftBarButtonItem = .doneButton { [weak settings] in
                    settings?.dismiss(animated: true)
                }
                self?.present(navigation, animated: true)
            }
            present(sheet, animated: true)
        }
    }
}

// MARK: - B: tip beside the reaction bar

/// A small bubble pointing at the reaction bar. Tapping it hides it; the
/// close button ends it for good.
final class IvyReactionBarTipView: UIView {

    /// Where the arrow points, in this view's superview.
    var target: CGPoint = .zero
    private let bubble = UIView()
    private let arrow = UIView()
    private let label = UILabel()
    private let close = UIButton(type: .system)
    static let maxWidth: CGFloat = 260

    override init(frame: CGRect) {
        super.init(frame: frame)
        bubble.backgroundColor = .Signal.accent
        bubble.layer.cornerRadius = 14
        bubble.layer.cornerCurve = .continuous
        arrow.backgroundColor = .Signal.accent
        arrow.transform = CGAffineTransform(rotationAngle: .pi / 4)
        addSubview(arrow)
        addSubview(bubble)

        let title = IvyLocalizedString("TIPS_BAR_TITLE", comment: "Title of the tip that points at the reaction bar.")
        let body = IvyLocalizedString("TIPS_BAR_BODY", comment: "Text of the tip that points at the reaction bar.")
        let text = NSMutableAttributedString(string: title + "\n", attributes: [.font: UIFont.dynamicTypeFootnote.semibold(), .foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: body, attributes: [.font: UIFont.dynamicTypeFootnote, .foregroundColor: UIColor.white]))
        label.attributedText = text
        label.numberOfLines = 0
        bubble.addSubview(label)

        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = UIColor.white.withAlphaComponent(0.8)
        close.accessibilityLabel = CommonStrings.dismissButton
        close.addAction(UIAction { [weak self] _ in
            IvyFirstTimeTips.closeBarTip()
            self?.hide()
        }, for: .primaryActionTriggered)
        bubble.addSubview(close)

        let tap = UITapGestureRecognizer(target: self, action: #selector(hideTapped))
        bubble.addGestureRecognizer(tap)
        isAccessibilityElement = false
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func hideTapped() {
        hide()
    }

    private func hide() {
        UIView.animate(withDuration: 0.2) { self.alpha = 0 } completion: { _ in self.removeFromSuperview() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, alpha == 0 else { return }
        UIView.animate(withDuration: 0.25, delay: 0.35) { self.alpha = 1 }
    }

    /// Fits the bubble into `area`, above the menu if there's room, else
    /// below the bar, with its arrow toward the bar.
    func place(barFrame: CGRect, menuTop: CGFloat, area: CGRect) {
        let width = min(Self.maxWidth, area.width)
        let labelSize = label.sizeThatFits(CGSize(width: width - 24 - 28, height: .greatestFiniteMagnitude))
        let height = labelSize.height + 20
        let x = min(max(area.minX, barFrame.midX - width / 2), area.maxX - width)
        let gap: CGFloat = 12
        let aboveY = min(menuTop, barFrame.minY) - gap - height
        let above = aboveY >= area.minY
        let y = above ? aboveY : barFrame.maxY + gap
        frame = CGRect(x: x, y: y, width: width, height: height)
        bubble.frame = bounds
        label.frame = CGRect(x: 12, y: 10, width: labelSize.width, height: labelSize.height)
        close.frame = CGRect(x: width - 32, y: 4, width: 28, height: 28)
        let arrowX = min(max(barFrame.midX - x, 18), width - 18)
        arrow.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
        arrow.center = CGPoint(x: arrowX, y: above ? height : 0)
        // The arrow only shows when the bubble is right at the bar, not when
        // the menu sits between them.
        let distance = above ? barFrame.minY - frame.maxY : frame.minY - barFrame.maxY
        arrow.isHidden = distance > gap + 4
    }
}

// MARK: - C: hint in the reactions sheet

/// A closable hint at the top of the reactions sheet.
final class IvyReactionsSheetHintView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        let box = UIView()
        box.backgroundColor = UIColor.Signal.accent.withAlphaComponent(0.2)
        box.layer.cornerRadius = 14
        box.layer.cornerCurve = .continuous
        addSubview(box)
        box.autoPinEdgesToSuperviewMargins()

        let label = UILabel()
        label.text = IvyLocalizedString("TIPS_SHEET_HINT", comment: "Hint at the top of a message's reactions the first time: the row at the bottom reacts, and double-tapping a message reacts too.")
        label.font = .dynamicTypeFootnote
        label.textColor = .Signal.label
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .Signal.secondaryLabel
        close.accessibilityLabel = CommonStrings.dismissButton
        close.addAction(UIAction { [weak self] _ in
            UIView.animate(withDuration: 0.2) { self?.isHidden = true }
        }, for: .primaryActionTriggered)
        close.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, close])
        row.alignment = .top
        row.spacing = 8
        box.addSubview(row)
        row.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 8))
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Settings

extension ChatsSettingsViewController {

    /// "Show Tips Again" under the reaction settings.
    func ivyAddTipsSection(to contents: OWSTableContents) {
        let section = OWSTableSection()
        section.add(.actionItem(
            withText: IvyLocalizedString("TIPS_SHOW_AGAIN", comment: "Item in chat settings that shows the first-time tips about reactions and the message menu again."),
            actionBlock: { [weak self] in
                IvyFirstTimeTips.reset()
                self?.presentToast(text: IvyLocalizedString("TIPS_SHOW_AGAIN_DONE", comment: "Shown after choosing to see the first-time tips again."))
            },
        ))
        contents.add(section)
    }
}
