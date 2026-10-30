//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - Day

/// A day in the week row or the month: its number, filled green when
/// selected, and a dot in the tone of each kind of item on it.
final class IvyDayButton: UIButton {

    var onTap: (() -> Void)?

    private let circle = UIView()
    private let numberLabel = UILabel()
    private let dots = UIStackView()
    private let diameter: CGFloat

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: .zero)
        circle.isUserInteractionEnabled = false
        circle.layer.cornerRadius = diameter / 2
        numberLabel.textAlignment = .center
        numberLabel.font = .monospacedDigitFont(ofSize: diameter * 0.47)
        dots.axis = .horizontal
        dots.spacing = 3
        dots.isUserInteractionEnabled = false
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .primaryActionTriggered)

        addSubview(circle)
        circle.addSubview(numberLabel)
        addSubview(dots)
        circle.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        dots.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: diameter),
            circle.heightAnchor.constraint(equalToConstant: diameter),
            numberLabel.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            dots.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 3),
            dots.centerXAnchor.constraint(equalTo: centerXAnchor),
            dots.heightAnchor.constraint(equalToConstant: 6),
            dots.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(day: Date, isSelected: Bool, isToday: Bool, isDimmed: Bool, tones: [IvyTone], calendar: Calendar) {
        numberLabel.text = "\(calendar.component(.day, from: day))"
        circle.backgroundColor = isSelected ? .Signal.accent : .clear
        if isSelected {
            numberLabel.textColor = .white
            numberLabel.font = UIFont.monospacedDigitFont(ofSize: diameter * 0.47).semibold()
        } else {
            numberLabel.textColor = isToday ? .Signal.accent : (isDimmed ? .Signal.tertiaryLabel : .Signal.label)
            numberLabel.font = isToday ? UIFont.monospacedDigitFont(ofSize: diameter * 0.47).semibold() : .monospacedDigitFont(ofSize: diameter * 0.47)
        }
        dots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tone in tones.prefix(3) {
            let dot = UIView()
            dot.backgroundColor = tone.strong
            dot.layer.cornerRadius = 3
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            dots.addArrangedSubview(dot)
        }
        accessibilityLabel = DateFormatter.localizedString(from: day, dateStyle: .full, timeStyle: .none)
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

extension IvyCalendar {
    /// The tones of what's on each day, in a fixed order, for the dots.
    static func tonesByDay(_ items: [IvyCalendarItem], in interval: DateInterval, calendar: Calendar = .current, now: Date = Date()) -> [Date: [IvyTone]] {
        let order: [IvyTone] = [.blue, .brown, .green, .red]
        var result = [Date: [IvyTone]]()
        for day in itemsByDay(items, in: interval, calendar: calendar) {
            let tones = Set(day.items.map { $0.tone(now: now) })
            result[day.day] = order.filter(tones.contains)
        }
        return result
    }
}

// MARK: - Week row

/// The week of the selected day: weekday letters, day numbers and dots.
/// Swiping moves a week back or ahead.
final class IvyWeekStrip: UIView {

    var onSelectDay: ((Date) -> Void)?
    var onMoveWeek: ((Int) -> Void)?

    private let weekdays = UIStackView()
    private let days = UIStackView()
    private(set) var dayButtons = [IvyDayButton]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        weekdays.axis = .horizontal
        weekdays.distribution = .fillEqually
        days.axis = .horizontal
        days.distribution = .fillEqually
        for _ in 0..<7 {
            let label = UILabel()
            label.font = UIFont.dynamicTypeCaption2Clamped.semibold()
            label.textColor = .Signal.secondaryLabel
            label.textAlignment = .center
            label.isAccessibilityElement = false
            weekdays.addArrangedSubview(label)
            let button = IvyDayButton(diameter: 38)
            days.addArrangedSubview(button)
            dayButtons.append(button)
        }
        let stack = UIStackView(arrangedSubviews: [weekdays, days])
        stack.axis = .vertical
        stack.spacing = 4
        addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()

        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selectedDay: Date, tones: [Date: [IvyTone]], calendar: Calendar) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else {
            return
        }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let today = calendar.startOfDay(for: Date())
        for index in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: index, to: week.start) else { continue }
            (weekdays.arrangedSubviews[index] as? UILabel)?.text = symbols[(index + calendar.firstWeekday - 1) % 7].localizedUppercase
            let button = dayButtons[index]
            button.configure(
                day: day,
                isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
                isToday: calendar.isDate(day, inSameDayAs: today),
                isDimmed: false,
                tones: tones[calendar.startOfDay(for: day)] ?? [],
                calendar: calendar,
            )
            button.onTap = { [weak self] in self?.onSelectDay?(day) }
        }
    }

    @objc
    private func didSwipe(_ swipe: UISwipeGestureRecognizer) {
        onMoveWeek?(swipe.direction == .left ? 1 : -1)
    }
}

// MARK: - Day timeline

/// A day as hours with a block for each timed item, all-day items above it
/// and, today, a line at the current time.
final class IvyDayTimelineView: UIView {

    var onOpen: ((IvyCalendarItem) -> Void)?

    static let hourHeight: CGFloat = 56
    private static let labelWidth: CGFloat = 50

    private let allDayScroll = UIScrollView()
    private let allDayStack = UIStackView()
    private let scrollView = UIScrollView()
    private let content = UIView()
    private var hourLabels = [UILabel]()
    private var hourLines = [UIView]()
    private let nowLine = UIView()
    private let nowDot = UIView()
    private var blocks = [(view: IvyTimelineBlock, item: IvyCalendarItem, column: Int, columns: Int)]()
    private var shownDay: Date?
    private var nowOffset: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        allDayStack.axis = .horizontal
        allDayStack.spacing = 8
        allDayScroll.showsHorizontalScrollIndicator = false
        allDayScroll.addSubview(allDayStack)
        allDayStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            allDayStack.topAnchor.constraint(equalTo: allDayScroll.contentLayoutGuide.topAnchor),
            allDayStack.bottomAnchor.constraint(equalTo: allDayScroll.contentLayoutGuide.bottomAnchor),
            allDayStack.leadingAnchor.constraint(equalTo: allDayScroll.contentLayoutGuide.leadingAnchor),
            allDayStack.trailingAnchor.constraint(equalTo: allDayScroll.contentLayoutGuide.trailingAnchor),
            allDayStack.heightAnchor.constraint(equalTo: allDayScroll.frameLayoutGuide.heightAnchor),
            allDayScroll.heightAnchor.constraint(equalToConstant: 34),
        ])

        for hour in 0...24 {
            let label = UILabel()
            label.font = .monospacedDigitFont(ofSize: 12)
            label.textColor = .Signal.secondaryLabel
            label.text = Self.hourText(hour)
            label.isAccessibilityElement = false
            content.addSubview(label)
            hourLabels.append(label)
            let line = UIView()
            line.backgroundColor = .Signal.opaqueSeparator
            content.addSubview(line)
            hourLines.append(line)
        }
        nowLine.backgroundColor = .Signal.accent
        nowDot.backgroundColor = .Signal.accent
        nowDot.layer.cornerRadius = 5
        content.addSubview(nowLine)
        content.addSubview(nowDot)
        scrollView.addSubview(content)

        let stack = UIStackView(arrangedSubviews: [allDayScroll, scrollView])
        stack.axis = .vertical
        stack.spacing = 8
        addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func hourText(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour % 24
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    func update(day: Date, items: [IvyCalendarItem], title: (IvyCalendarItem) -> String, calendar: Calendar) {
        let start = calendar.startOfDay(for: day)

        allDayStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let allDay = items.filter(\.isAllDay)
        for item in allDay {
            let tone = item.tone()
            var configuration = UIButton.Configuration.filled()
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = tone.background
            configuration.baseForegroundColor = tone.text
            var text = AttributedString(title(item))
            text.font = UIFont.dynamicTypeFootnoteClamped.semibold()
            configuration.attributedTitle = text
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            let chip = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.onOpen?(item) })
            allDayStack.addArrangedSubview(chip)
        }
        allDayScroll.isHidden = allDay.isEmpty

        blocks.forEach { $0.view.removeFromSuperview() }
        blocks = []
        for placed in Self.columns(for: items.filter { !$0.isAllDay }) {
            let block = IvyTimelineBlock(item: placed.item, title: title(placed.item))
            block.addAction(UIAction { [weak self] _ in self?.onOpen?(placed.item) }, for: .touchUpInside)
            content.addSubview(block)
            blocks.append((view: block, item: placed.item, column: placed.column, columns: placed.columns))
        }

        let now = Date()
        if calendar.isDate(now, inSameDayAs: start) {
            nowOffset = CGFloat(now.timeIntervalSince(start) / 3600) * Self.hourHeight
        } else {
            nowOffset = nil
        }
        nowLine.isHidden = nowOffset == nil
        nowDot.isHidden = nowOffset == nil

        setNeedsLayout()
        layoutIfNeeded()
        if shownDay != start {
            shownDay = start
            let firstHour = items.filter { !$0.isAllDay }.map { $0.start.timeIntervalSince(start) / 3600 }.min()
            let focus = nowOffset.map { $0 / Self.hourHeight } ?? firstHour ?? 8
            let offset = max(0, CGFloat(focus - 1) * Self.hourHeight)
            scrollView.contentOffset.y = min(offset, max(0, scrollView.contentSize.height - scrollView.bounds.height))
        }
    }

    /// Overlapping items share the width side by side.
    static func columns(for items: [IvyCalendarItem]) -> [(item: IvyCalendarItem, column: Int, columns: Int)] {
        let sorted = items.sorted { $0.start < $1.start }
        var result = [(item: IvyCalendarItem, column: Int, columns: Int)]()
        var cluster = [(item: IvyCalendarItem, column: Int)]()
        var columnEnds = [Date]()
        var clusterEnd = Date.distantPast
        func finish() {
            result += cluster.map { (item: $0.item, column: $0.column, columns: columnEnds.count) }
            cluster = []
            columnEnds = []
        }
        for item in sorted {
            let end = max(item.end, item.start.addingTimeInterval(30 * 60))
            if item.start >= clusterEnd {
                finish()
            }
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = end
                cluster.append((item: item, column: free))
            } else {
                columnEnds.append(end)
                cluster.append((item: item, column: columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, end)
        }
        finish()
        return result
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = scrollView.bounds.width
        let height = Self.hourHeight * 24 + 20
        content.frame = CGRect(x: 0, y: 0, width: width, height: height)
        scrollView.contentSize = content.frame.size
        let top: CGFloat = 10
        for hour in 0...24 {
            let y = top + CGFloat(hour) * Self.hourHeight
            hourLabels[hour].frame = CGRect(x: 0, y: y - 8, width: Self.labelWidth - 6, height: 16)
            hourLines[hour].frame = CGRect(x: Self.labelWidth, y: y, width: width - Self.labelWidth, height: 1 / max(traitCollection.displayScale, 1))
        }
        if let nowOffset {
            nowLine.frame = CGRect(x: Self.labelWidth, y: top + nowOffset - 1, width: width - Self.labelWidth, height: 2)
            nowDot.frame = CGRect(x: Self.labelWidth - 5, y: top + nowOffset - 5, width: 10, height: 10)
            content.bringSubviewToFront(nowLine)
            content.bringSubviewToFront(nowDot)
        }
        guard let day = shownDay ?? blocks.first.map({ Calendar.current.startOfDay(for: $0.item.start) }) else {
            return
        }
        let area = width - Self.labelWidth - 4
        for block in blocks {
            let startHours = max(0, block.item.start.timeIntervalSince(day) / 3600)
            let endHours = min(24, max(block.item.end, block.item.start.addingTimeInterval(30 * 60)).timeIntervalSince(day) / 3600)
            let columnWidth = area / CGFloat(block.columns)
            block.view.frame = CGRect(
                x: Self.labelWidth + 4 + CGFloat(block.column) * columnWidth,
                y: top + CGFloat(startHours) * Self.hourHeight + 1,
                width: columnWidth - 3,
                height: max(28, CGFloat(endHours - startHours) * Self.hourHeight - 2),
            )
        }
    }
}

/// An item on the timeline: a tinted block with a bar in its tone.
final class IvyTimelineBlock: UIControl {

    init(item: IvyCalendarItem, title: String) {
        super.init(frame: .zero)
        let tone = item.tone()
        backgroundColor = tone.background
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let bar = UIView()
        bar.backgroundColor = tone.strong
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.dynamicTypeFootnoteClamped.semibold()
        titleLabel.textColor = tone.text
        let timeLabel = UILabel()
        timeLabel.text = IvyCalendarUI.timeText(for: item)
        timeLabel.font = .dynamicTypeCaption1Clamped
        timeLabel.textColor = tone.strong
        let texts = UIStackView(arrangedSubviews: [titleLabel, timeLabel])
        texts.axis = .vertical
        texts.spacing = 1
        texts.isUserInteractionEnabled = false
        addSubview(bar)
        addSubview(texts)
        bar.translatesAutoresizingMaskIntoConstraints = false
        texts.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 4),
            texts.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            texts.topAnchor.constraint(equalTo: topAnchor, constant: 5),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title + ", " + IvyCalendarUI.timeText(for: item)
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}
