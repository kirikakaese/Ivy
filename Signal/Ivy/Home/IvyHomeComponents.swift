//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - Header

/// The top of Home: the date and a greeting, four quick actions, and a card
/// with what's happening now or next.
final class IvyHomeHeaderView: UIView {

    struct QuickAction {
        let title: String
        let systemImage: String
        let action: () -> Void
    }

    var quickActions: [QuickAction] = [] {
        didSet { buildQuickActions() }
    }

    /// Opens the item on the card, or the calendar when nothing is next.
    var onOpenNextUp: ((IvyCalendarItem?) -> Void)?

    private let dateLabel = UILabel()
    private let greetingLabel = UILabel()
    private let tiles = UIStackView()
    private let card = UIView()
    private let cardCaption = UILabel()
    private let cardTitle = UILabel()
    private let cardDetail = UILabel()
    private let cardThen = UILabel()
    private var nextItem: IvyCalendarItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preservesSuperviewLayoutMargins = true

        dateLabel.font = UIFont.dynamicTypeFootnote.semibold()
        dateLabel.textColor = .Signal.secondaryLabel
        dateLabel.adjustsFontForContentSizeCategory = true
        greetingLabel.font = UIFont.dynamicTypeLargeTitle1Clamped.semibold()
        greetingLabel.textColor = .Signal.label
        greetingLabel.adjustsFontForContentSizeCategory = true
        greetingLabel.numberOfLines = 0
        greetingLabel.accessibilityTraits = .header

        tiles.axis = .horizontal
        tiles.distribution = .fillEqually
        tiles.spacing = 10

        let tone = IvyTone.blue
        card.backgroundColor = tone.background
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        cardCaption.font = UIFont.dynamicTypeFootnote.semibold()
        cardCaption.textColor = tone.strong
        cardTitle.font = UIFont.dynamicTypeHeadline
        cardTitle.textColor = .Signal.label
        cardTitle.numberOfLines = 2
        cardDetail.font = .dynamicTypeSubheadline
        cardDetail.textColor = tone.strong
        cardDetail.numberOfLines = 2
        cardThen.font = .dynamicTypeFootnote
        cardThen.textColor = tone.strong
        cardThen.numberOfLines = 2
        for label in [cardCaption, cardTitle, cardDetail, cardThen] {
            label.adjustsFontForContentSizeCategory = true
        }
        let cardStack = UIStackView(arrangedSubviews: [cardCaption, cardTitle, cardDetail, cardThen])
        cardStack.axis = .vertical
        cardStack.spacing = 3
        cardStack.setCustomSpacing(6, after: cardCaption)
        cardStack.setCustomSpacing(10, after: cardDetail)
        card.addSubview(cardStack)
        cardStack.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18))
        card.isAccessibilityElement = true
        card.accessibilityTraits = .button
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openNextUp)))

        let stack = UIStackView(arrangedSubviews: [dateLabel, greetingLabel, tiles, card])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(16, after: greetingLabel)
        stack.setCustomSpacing(18, after: tiles)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildQuickActions() {
        tiles.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for quickAction in quickActions {
            var configuration = UIButton.Configuration.gray()
            configuration.image = UIImage(systemName: quickAction.systemImage, withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3))
            configuration.baseForegroundColor = .Signal.accent
            configuration.background.cornerRadius = 18
            configuration.cornerStyle = .fixed
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in quickAction.action() })
            button.accessibilityLabel = quickAction.title
            button.toolTip = quickAction.title
            button.heightAnchor.constraint(equalToConstant: 56).isActive = true

            let label = UILabel()
            label.text = quickAction.title
            label.font = .dynamicTypeFootnoteClamped
            label.textColor = .Signal.label
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.75
            label.isAccessibilityElement = false

            let tile = UIStackView(arrangedSubviews: [button, label])
            tile.axis = .vertical
            tile.spacing = 6
            tiles.addArrangedSubview(tile)
        }
    }

    // MARK: -

    func update(now: Date, nextUp: (item: IvyCalendarItem, following: IvyCalendarItem?)?, title: (IvyCalendarItem) -> String) {
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        dateLabel.text = dateFormatter.string(from: now).localizedUppercase
        greetingLabel.text = Self.greeting(at: now)

        nextItem = nextUp?.item
        let nextUpTitle = IvyLocalizedString("HOME_NEXT_UP", comment: "Caption of the card on Home with what's happening next.")
        guard let nextUp else {
            cardCaption.text = nextUpTitle.localizedUppercase
            cardTitle.text = IvyLocalizedString("HOME_NOTHING_LEFT_TODAY", comment: "Shown on Home when nothing else is planned for today.")
            cardDetail.text = IvyLocalizedString("HOME_OPEN_CALENDAR", comment: "Item on Home that opens the calendar.")
            cardThen.isHidden = true
            updateCardAccessibility()
            return
        }
        cardCaption.text = (nextUpTitle + " · " + Self.when(nextUp.item, now: now)).localizedUppercase
        cardTitle.text = title(nextUp.item)
        var detail = IvyCalendarUI.timeText(for: nextUp.item)
        if case .event(let event) = nextUp.item.kind, !event.location.isEmpty {
            detail += " · " + event.location
        }
        cardDetail.text = detail
        if let following = nextUp.following {
            let time = DateFormatter.localizedString(from: following.start, dateStyle: .none, timeStyle: .short)
            cardThen.text = String(
                format: IvyLocalizedString("HOME_NEXT_THEN_FORMAT", comment: "Last line of the card on Home: what comes after the next item. Embeds {{ time and title }}."),
                time + " " + title(following),
            )
            cardThen.isHidden = false
        } else {
            cardThen.isHidden = true
        }
        updateCardAccessibility()
    }

    private func updateCardAccessibility() {
        card.accessibilityLabel = [cardCaption, cardTitle, cardDetail, cardThen]
            .filter { !$0.isHidden }
            .compactMap(\.text)
            .joined(separator: ", ")
    }

    /// "Good morning", "Good afternoon", "Good evening", or late at night
    /// "Still up?".
    static func greeting(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11:
            return IvyLocalizedString("HOME_GREETING_MORNING", comment: "Greeting on Home from 5 to 11 o'clock.")
        case 11..<18:
            return IvyLocalizedString("HOME_GREETING_DAY", comment: "Greeting on Home from 11 to 18 o'clock.")
        case 18..<23:
            return IvyLocalizedString("HOME_GREETING_EVENING", comment: "Greeting on Home from 18 to 23 o'clock.")
        default:
            return IvyLocalizedString("HOME_GREETING_NIGHT", comment: "Greeting on Home late at night, from 23 to 5 o'clock.")
        }
    }

    /// "Now", "In 45 min" or "Tomorrow".
    static func when(_ item: IvyCalendarItem, now: Date, calendar: Calendar = .current) -> String {
        if item.start <= now {
            return IvyLocalizedString("HOME_NEXT_NOW", comment: "On Home's card: the next item is happening now.")
        }
        if !calendar.isDate(item.start, inSameDayAs: now) {
            return IvyLocalizedString("HOME_NEXT_TOMORROW", comment: "On Home's card: the next item is tomorrow.")
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 1
        let minutes = (item.start.timeIntervalSince(now) / 60).rounded(.up)
        let text = formatter.string(from: max(minutes, 1) * 60) ?? ""
        return String(format: IvyLocalizedString("HOME_NEXT_IN_FORMAT", comment: "On Home's card: how soon the next item starts. Embeds {{ a duration like 45 min }}."), text)
    }

    @objc
    private func openNextUp() {
        onOpenNextUp?(nextItem)
    }
}

// MARK: - Important message

/// An important message as a chat row: the chat's picture, name and time,
/// the message, and a tag saying why it's here.
final class IvyImportantCell: UITableViewCell {

    static let reuseIdentifier = "IvyImportantCell"

    private let avatarView = ConversationAvatarView(sizeClass: .fortyEight, localUserDisplayMode: .asUser)
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let previewLabel = UILabel()
    private let tagLabel = IvyTagLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        nameLabel.font = UIFont.dynamicTypeBody.semibold()
        nameLabel.adjustsFontForContentSizeCategory = true
        timeLabel.font = .dynamicTypeFootnote
        timeLabel.textColor = .Signal.secondaryLabel
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        previewLabel.font = .dynamicTypeSubheadline
        previewLabel.textColor = .Signal.secondaryLabel
        previewLabel.numberOfLines = 2
        previewLabel.adjustsFontForContentSizeCategory = true

        let topRow = UIStackView(arrangedSubviews: [nameLabel, timeLabel])
        topRow.axis = .horizontal
        topRow.alignment = .firstBaseline
        topRow.spacing = 8
        let tagRow = UIStackView(arrangedSubviews: [tagLabel, UIView()])
        tagRow.axis = .horizontal
        let texts = UIStackView(arrangedSubviews: [topRow, previewLabel, tagRow])
        texts.axis = .vertical
        texts.spacing = 2
        texts.setCustomSpacing(6, after: previewLabel)
        let row = UIStackView(arrangedSubviews: [avatarView, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(thread: TSThread, chatName: String, sender: String?, text: String, date: Date, reason: String, tone: IvyTone) {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            avatarView.update(tx) { config in
                config.dataSource = .thread(thread)
            }
        }
        nameLabel.text = chatName
        timeLabel.text = DateUtil.formatDynamicDateShort(date).formatted
        let preview = NSMutableAttributedString()
        if let sender {
            preview.append(NSAttributedString(string: sender + ": ", attributes: [.font: UIFont.dynamicTypeSubheadline.semibold()]))
        }
        preview.append(NSAttributedString(string: text))
        previewLabel.attributedText = preview
        tagLabel.configure(text: reason, tone: tone)
        accessibilityLabel = [chatName, reason, sender, text].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A small tag in a pastel tone.
final class IvyTagLabel: UILabel {

    private let insets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFont.dynamicTypeCaption1.semibold()
        adjustsFontForContentSizeCategory = true
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, tone: IvyTone) {
        self.text = text
        textColor = tone.tagText
        backgroundColor = tone.button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

// MARK: - Folder chips

/// Folders with unread chats, as chips in their colour.
final class IvyFolderChipsCell: UITableViewCell {

    static let reuseIdentifier = "IvyFolderChipsCell"

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        selectionStyle = .none
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        stack.axis = .horizontal
        stack.spacing = 8
        contentView.addSubview(scrollView)
        scrollView.addSubview(stack)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ chips: [(title: String, count: Int, color: UIColor, action: () -> Void)]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for chip in chips {
            var configuration = UIButton.Configuration.filled()
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = chip.color.withAlphaComponent(0.16)
            configuration.baseForegroundColor = chip.color
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            var title = AttributedString(chip.title + "  " + chip.count.formatted())
            title.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
            configuration.attributedTitle = title
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in chip.action() })
            button.accessibilityLabel = chip.title
            button.accessibilityValue = String.localizedStringWithFormat(
                IvyLocalizedString("CHAT_FOLDER_UNREAD_COUNT_FORMAT", comment: "Accessibility value of a chat folder tab. Embeds {{ the number of chats with unread messages }}."),
                chip.count,
            )
            stack.addArrangedSubview(button)
        }
    }
}
