//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A date found in a message's text, on the device.
public struct IvyDetectedDate: Equatable, Sendable {
    public let date: Date
    public let duration: TimeInterval?
    /// True when the text names a day without a time.
    public let isAllDay: Bool
    /// The text that names the date.
    public let text: String

    public init(date: Date, duration: TimeInterval?, isAllDay: Bool, text: String) {
        self.date = date
        self.duration = duration
        self.isAllDay = isAllDay
        self.text = text
    }
}

public enum IvyDateDetection {

    /// Dates in `text`, in the order they appear. Only the device looks at
    /// the text.
    public static func dates(in text: String) -> [IvyDetectedDate] {
        guard
            !text.isEmpty,
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let date = match.date, let matchRange = Range(match.range, in: text) else {
                return nil
            }
            let matchedText = String(text[matchRange])
            return IvyDetectedDate(
                date: date,
                duration: match.duration > 0 ? match.duration : nil,
                isAllDay: !namesTime(matchedText),
                text: matchedText,
            )
        }
    }

    /// The first date in `text` that isn't in the past, or nil.
    public static func firstUpcomingDate(in text: String, now: Date = Date(), calendar: Calendar = .current) -> IvyDetectedDate? {
        let today = calendar.startOfDay(for: now)
        return dates(in: text).first { $0.date >= today }
    }

    /// Whether the matched text names a time of day, not only a day. The
    /// detector puts date-only matches at noon, so the text decides.
    static func namesTime(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil {
            return true
        }
        let timeWords = ["am", "pm", "a.m.", "p.m.", "uhr", "noon", "midnight", "mittag", "morning", "evening", "tonight", "abend", "morgens"]
        return timeWords.contains { word in
            lowercased.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: .regularExpression) != nil
                || (word.hasSuffix(".") && lowercased.contains(word))
        }
    }
}

// MARK: - Calendar items

/// Something shown in the calendar: one occurrence of an event, a task with
/// a due date, or an open reminder.
public struct IvyCalendarItem: Equatable, Identifiable, Sendable {

    public enum Kind: Equatable, Sendable {
        case event(IvyEvent)
        case task(IvyTask)
        case reminder(IvyReminder)
    }

    public let kind: Kind
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public var id: String {
        switch kind {
        case .event(let event): return "event-\(event.id)-\(Int64(start.timeIntervalSince1970))"
        case .task(let task): return "task-\(task.id)"
        case .reminder(let reminder): return "reminder-\(reminder.id)"
        }
    }

    /// Sorts all-day items first, then by start.
    public static func areInIncreasingOrder(_ lhs: IvyCalendarItem, _ rhs: IvyCalendarItem) -> Bool {
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay
        }
        return (lhs.start, lhs.id) < (rhs.start, rhs.id)
    }
}

public enum IvyCalendar {

    /// The items that overlap `interval`.
    public static func items(
        events: [IvyEvent],
        tasks: [IvyTask],
        reminders: [IvyReminder],
        in interval: DateInterval,
        calendar: Calendar = .current,
    ) -> [IvyCalendarItem] {
        var items = [IvyCalendarItem]()
        for event in events {
            let duration = event.duration(calendar: calendar)
            for start in event.occurrences(in: interval, calendar: calendar) {
                items.append(IvyCalendarItem(
                    kind: .event(event),
                    start: start,
                    end: start.addingTimeInterval(duration),
                    isAllDay: event.isAllDay,
                ))
            }
        }
        for task in tasks where !task.isDone {
            guard let dueAt = task.dueAt, interval.contains(dueAt) else {
                continue
            }
            items.append(IvyCalendarItem(kind: .task(task), start: dueAt, end: dueAt, isAllDay: task.isAllDay))
        }
        for reminder in reminders where !reminder.isDone && interval.contains(reminder.dueAt) {
            items.append(IvyCalendarItem(kind: .reminder(reminder), start: reminder.dueAt, end: reminder.dueAt, isAllDay: false))
        }
        return items.sorted(by: IvyCalendarItem.areInIncreasingOrder)
    }

    /// The items of each day in `interval`, for days that have any. An event
    /// over several days appears on each of them.
    public static func itemsByDay(
        _ items: [IvyCalendarItem],
        in interval: DateInterval,
        calendar: Calendar = .current,
    ) -> [(day: Date, items: [IvyCalendarItem])] {
        var result = [(day: Date, items: [IvyCalendarItem])]()
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            let dayItems = items.filter { item in
                if item.start == item.end {
                    return item.start >= day && item.start < nextDay
                }
                return item.start < nextDay && item.end > day
            }
            if !dayItems.isEmpty {
                result.append((day, dayItems))
            }
            day = nextDay
        }
        return result
    }

    /// The days shown in a month view: whole weeks from the week of the
    /// first day to the week of the last day.
    public static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard
            let month = calendar.dateInterval(of: .month, for: date),
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
            let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)
        else {
            return []
        }
        var days = [Date]()
        var day = firstWeek.start
        while day < lastWeek.end, days.count < 42 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }
        return days
    }
}
