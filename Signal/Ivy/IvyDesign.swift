//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Ivy's pastel tones, as soft as Signal's reminders: for kinds of calendar
/// items, Home's cards and Ivy Status.
enum IvyTone {
    case blue
    case brown
    case green
    case red
    /// Neutral, for states that aren't a warning (being offline).
    case gray

    /// Dots, bars and icons.
    var strong: UIColor {
        switch self {
        case .blue: return Self.color(light: 0x5B8FD0, dark: 0x8FB0DA)
        case .brown: return Self.color(light: 0xC08A52, dark: 0xC79869)
        case .green: return Self.color(light: 0x4FA676, dark: 0x86C29E)
        case .red: return Self.color(light: 0xD0675E, dark: 0xDE8F87)
        case .gray: return Self.color(light: 0x8E8E93, dark: 0x98989F)
        }
    }

    /// Text on a tinted card: the system's in light mode, the tone in dark.
    var text: UIColor {
        switch self {
        case .blue: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0x8FB0DA))
        case .brown: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0xC79869))
        case .green: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0x86C29E))
        case .red: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0xDE8F87))
        case .gray: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0xD1D1D6))
        }
    }

    /// A tinted card. Brown is the warning colour of SignalUI's ReminderView.
    var background: UIColor {
        switch self {
        case .blue: return Self.color(light: 0xEBF2FB, dark: 0x1C222B)
        case .brown: return Self.color(light: 0xFBF2E9, dark: 0x26221D)
        case .green: return Self.color(light: 0xEBF6EF, dark: 0x1C2520)
        case .red: return Self.color(light: 0xFCEDEB, dark: 0x2A1D1C)
        case .gray: return Self.color(light: 0xF0F0F2, dark: 0x232326)
        }
    }

    /// Buttons and tags on a tinted card, a little stronger.
    var button: UIColor {
        switch self {
        case .blue: return Self.color(light: 0xD3E3F5, dark: 0x26313F)
        case .brown: return Self.color(light: 0xF4DDC7, dark: 0x392D22)
        case .green: return Self.color(light: 0xD3EBDC, dark: 0x26372D)
        case .red: return Self.color(light: 0xF6D5D1, dark: 0x422926)
        case .gray: return Self.color(light: 0xE0E0E4, dark: 0x343438)
        }
    }

    /// Text on a tag, readable in both modes.
    var tagText: UIColor {
        switch self {
        case .blue: return Self.color(light: 0x2C5A96, dark: 0x8FB0DA)
        case .brown: return Self.color(light: 0x8A5A2B, dark: 0xC79869)
        case .green: return Self.color(light: 0x2B6B45, dark: 0x86C29E)
        case .red: return Self.color(light: 0xA8352F, dark: 0xDE8F87)
        case .gray: return Self.color(light: 0x56565C, dark: 0xC7C7CC)
        }
    }

    private static func color(light: UInt32, dark: UInt32) -> UIColor {
        UIColor(light: UIColor(rgbHex: light), dark: UIColor(rgbHex: dark))
    }
}

extension IvyCalendarItem {
    /// Events blue, reminders brown, tasks green, overdue tasks red.
    func tone(now: Date = Date()) -> IvyTone {
        switch kind {
        case .event: return .blue
        case .reminder: return .brown
        case .task(let task): return task.isOverdue(at: now) ? .red : .green
        }
    }
}

// MARK: - Section header

/// A section heading as in Signal's chat list: bold, with a date or an
/// "All" button on the trailing side.
final class IvySectionHeaderView: UITableViewHeaderFooterView {

    static let reuseIdentifier = "IvySectionHeader"

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let actionButton = UIButton(type: .system)
#if targetEnvironment(macCatalyst)
    private let actionLabel = UILabel()
#endif
    private var action: (() -> Void)?
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?

    /// Where the table's cards start, so the heading lines up with their
    /// edge rather than with the text inside them.
    var cardInset: CGFloat = 0 {
        didSet {
            leading?.constant = cardInset + 4
            trailing?.constant = -(cardInset + 4)
        }
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        titleLabel.font = UIFont.dynamicTypeTitle3.semibold()
        titleLabel.textColor = .Signal.label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
#if targetEnvironment(macCatalyst)
        // Small gray labels on the Mac, like "Fixiert" in Chats.
        titleLabel.font = UIFont.dynamicTypeFootnoteClamped.semibold()
        titleLabel.textColor = .Signal.secondaryLabel
#endif
        detailLabel.font = .dynamicTypeSubheadline
        detailLabel.textColor = .Signal.secondaryLabel
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.titleLabel?.font = .dynamicTypeSubheadline
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.tintColor = .Signal.accent
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.addAction(UIAction { [weak self] _ in self?.action?() }, for: .primaryActionTriggered)

#if targetEnvironment(macCatalyst)
        // On the Mac the action is a label, not a button. The Mac's own
        // button is a boxed push button that sits off the heading's line,
        // and lining a button up on the heading's baseline ties the stack
        // to the button's title label, which the Mac refuses: it stopped
        // the app on Start and in the calendar.
        actionLabel.font = .dynamicTypeSubheadline
        actionLabel.adjustsFontForContentSizeCategory = true
        actionLabel.textColor = .Signal.accent
        actionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionLabel.isUserInteractionEnabled = true
        actionLabel.isAccessibilityElement = true
        actionLabel.accessibilityTraits = .button
        actionLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapAction)))
        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), detailLabel, actionLabel])
#else
        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), detailLabel, actionButton])
#endif
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let leading = stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4)
        let trailing = stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4)
        self.leading = leading
        self.trailing = trailing
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UIDevice.current.userInterfaceIdiom == .mac ? 16 : 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: UIDevice.current.userInterfaceIdiom == .mac ? -6 : -8),
            leading,
            trailing,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

#if targetEnvironment(macCatalyst)
    @objc
    private func didTapAction() {
        action?()
    }
#endif

    func configure(title: String, detail: String? = nil, detailColor: UIColor = .Signal.secondaryLabel, actionTitle: String? = nil, action: (() -> Void)? = nil) {
#if targetEnvironment(macCatalyst)
        titleLabel.text = title.localizedUppercase
        accessibilityLabel = title
#else
        titleLabel.text = title
#endif
        detailLabel.text = detail
        detailLabel.textColor = detailColor
        detailLabel.isHidden = detail == nil
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
#if targetEnvironment(macCatalyst)
        actionLabel.text = actionTitle
        actionLabel.isHidden = actionTitle == nil
#endif
        self.action = action
        accessibilityTraits = .header
    }
}

// MARK: - Agenda row

/// A calendar item: a bar in its tone, the time, a checkbox for tasks, the
/// title and a line of detail.
final class IvyAgendaCell: UITableViewCell {

    static let reuseIdentifier = "IvyAgendaCell"

    private let bar = UIView()
    private let timeLabel = UILabel()
    private let checkbox = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        bar.layer.cornerRadius = 2
        bar.widthAnchor.constraint(equalToConstant: 4).isActive = true

        timeLabel.font = .monospacedDigitFont(ofSize: UIFont.dynamicTypeSubheadline.pointSize)
        timeLabel.textColor = .Signal.secondaryLabel
        timeLabel.numberOfLines = 2
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        checkbox.contentMode = .scaleAspectFit
        checkbox.tintColor = .Signal.secondaryLabel
        checkbox.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = UIFont.dynamicTypeBody.semibold()
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .dynamicTypeFootnote
        detailLabel.textColor = .Signal.secondaryLabel
        detailLabel.numberOfLines = 2
        detailLabel.adjustsFontForContentSizeCategory = true

        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 2
        let row = UIStackView(arrangedSubviews: [bar, timeLabel, checkbox, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.setCustomSpacing(10, after: checkbox)
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
        let fullHeight = bar.heightAnchor.constraint(equalTo: row.heightAnchor)
        fullHeight.priority = .defaultHigh
        fullHeight.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: IvyCalendarItem, title: String, detail: String?) {
        let tone = item.tone()
        bar.backgroundColor = tone.strong
        timeLabel.text = IvyCalendarUI.shortTimeText(for: item)
        titleLabel.text = title
        detailLabel.text = detail
        detailLabel.isHidden = detail?.isEmpty ?? true
        detailLabel.textColor = tone == .red ? tone.strong : .Signal.secondaryLabel
        if case .task(let task) = item.kind {
            checkbox.image = IvyTaskUI.checkboxImage(isDone: task.isDone)
            checkbox.isHidden = false
        } else {
            checkbox.isHidden = true
        }
        accessibilityLabel = [timeLabel.text?.replacingOccurrences(of: "\n", with: " – "), title, detail].compactMap { $0 }.joined(separator: ", ")
    }
}
