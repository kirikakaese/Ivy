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

    /// Dots, bars and icons.
    var strong: UIColor {
        switch self {
        case .blue: return Self.color(light: 0x5B8FD0, dark: 0x8FB0DA)
        case .brown: return Self.color(light: 0xC08A52, dark: 0xC79869)
        case .green: return Self.color(light: 0x4FA676, dark: 0x86C29E)
        case .red: return Self.color(light: 0xD0675E, dark: 0xDE8F87)
        }
    }

    /// Text on a tinted card: the system's in light mode, the tone in dark.
    var text: UIColor {
        switch self {
        case .blue: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0x8FB0DA))
        case .brown: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0xC79869))
        case .green: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0x86C29E))
        case .red: return UIColor(light: .Signal.label, dark: UIColor(rgbHex: 0xDE8F87))
        }
    }

    /// A tinted card. Brown is the warning colour of SignalUI's ReminderView.
    var background: UIColor {
        switch self {
        case .blue: return Self.color(light: 0xEBF2FB, dark: 0x1C222B)
        case .brown: return Self.color(light: 0xFBF2E9, dark: 0x26221D)
        case .green: return Self.color(light: 0xEBF6EF, dark: 0x1C2520)
        case .red: return Self.color(light: 0xFCEDEB, dark: 0x2A1D1C)
        }
    }

    /// Buttons and tags on a tinted card, a little stronger.
    var button: UIColor {
        switch self {
        case .blue: return Self.color(light: 0xD3E3F5, dark: 0x26313F)
        case .brown: return Self.color(light: 0xF4DDC7, dark: 0x392D22)
        case .green: return Self.color(light: 0xD3EBDC, dark: 0x26372D)
        case .red: return Self.color(light: 0xF6D5D1, dark: 0x422926)
        }
    }

    /// Text on a tag, readable in both modes.
    var tagText: UIColor {
        switch self {
        case .blue: return Self.color(light: 0x2C5A96, dark: 0x8FB0DA)
        case .brown: return Self.color(light: 0x8A5A2B, dark: 0xC79869)
        case .green: return Self.color(light: 0x2B6B45, dark: 0x86C29E)
        case .red: return Self.color(light: 0xA8352F, dark: 0xDE8F87)
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
        detailLabel.font = .dynamicTypeSubheadline
        detailLabel.textColor = .Signal.secondaryLabel
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.titleLabel?.font = .dynamicTypeSubheadline
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.tintColor = .Signal.accent
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.addAction(UIAction { [weak self] _ in self?.action?() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), detailLabel, actionButton])
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
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            leading,
            trailing,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String? = nil, detailColor: UIColor = .Signal.secondaryLabel, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        titleLabel.text = title
        detailLabel.text = detail
        detailLabel.textColor = detailColor
        detailLabel.isHidden = detail == nil
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
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
