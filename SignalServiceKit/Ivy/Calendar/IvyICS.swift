//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Reads and writes iCalendar (`.ics`, RFC 5545) files, so events can move
/// between Ivy and other calendar apps, and be sent in a chat as a file.
public enum IvyICS {

    public static let fileExtension = "ics"
    public static let mimeType = "text/calendar"

    // MARK: - Writing

    public static func export(_ events: [IvyEvent], now: Date = Date(), calendar: Calendar = .current) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Ivy//Ivy//EN",
            "CALSCALE:GREGORIAN",
        ]
        for event in events {
            lines += eventLines(event, now: now, calendar: calendar)
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func eventLines(_ event: IvyEvent, now: Date, calendar: Calendar) -> [String] {
        var lines = ["BEGIN:VEVENT"]
        lines.append("UID:" + escape(event.importedUID ?? "\(event.id)@ivy"))
        lines.append("DTSTAMP:" + utcString(now))
        if event.isAllDay {
            let lastDay = calendar.startOfDay(for: event.endAt)
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            lines.append("DTSTART;VALUE=DATE:" + dateString(event.startAt, calendar: calendar))
            lines.append("DTEND;VALUE=DATE:" + dateString(end, calendar: calendar))
        } else {
            lines.append("DTSTART:" + utcString(event.startAt))
            lines.append("DTEND:" + utcString(event.endAt))
        }
        lines.append("SUMMARY:" + escape(event.title))
        if !event.location.isEmpty {
            lines.append("LOCATION:" + escape(event.location))
        }
        if !event.notes.isEmpty {
            lines.append("DESCRIPTION:" + escape(event.notes))
        }
        if let recurrence = event.recurrence {
            var rule = "RRULE:FREQ=" + recurrence.frequency.rawValue.uppercased()
            if recurrence.interval > 1 {
                rule += ";INTERVAL=\(recurrence.interval)"
            }
            if let until = recurrence.until {
                rule += ";UNTIL=" + (event.isAllDay ? dateString(until, calendar: calendar) : utcString(until))
            }
            lines.append(rule)
        }
        if let minutes = event.alertMinutes {
            lines += [
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                "DESCRIPTION:" + escape(event.title),
                "TRIGGER:" + (minutes == 0 ? "PT0M" : "-PT\(minutes)M"),
                "END:VALARM",
            ]
        }
        lines.append("END:VEVENT")
        return lines
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next line after a space.
    static func fold(_ line: String) -> String {
        var result = ""
        var lineBytes = 0
        for character in line {
            let bytes = String(character).utf8.count
            if lineBytes + bytes > 75 {
                result += "\r\n "
                lineBytes = 1
            }
            result.append(character)
            lineBytes += bytes
        }
        return result
    }

    private static func utcString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    // MARK: - Reading

    public enum ImportError: Error {
        case notACalendar
    }

    /// The events in an `.ics` file. Entries this reader doesn't understand
    /// are skipped.
    public static func parse(_ text: String, calendar: Calendar = .current) throws -> [IvyEvent] {
        let lines = unfold(text)
        guard lines.contains(where: { $0.uppercased().hasPrefix("BEGIN:VCALENDAR") }) else {
            throw ImportError.notACalendar
        }
        var events = [IvyEvent]()
        var properties: [Property]?
        var alarmDepth = 0
        var alarmTriggers = [String]()
        for line in lines {
            guard let property = Property(line: line) else {
                continue
            }
            switch (property.name, property.value.uppercased()) {
            case ("BEGIN", "VEVENT"):
                properties = []
                alarmTriggers = []
            case ("END", "VEVENT"):
                if let properties, let parsed = event(from: properties, alarmTriggers: alarmTriggers, calendar: calendar) {
                    events.append(parsed)
                }
                properties = nil
            case ("BEGIN", "VALARM"):
                alarmDepth += 1
            case ("END", "VALARM"):
                alarmDepth = max(alarmDepth - 1, 0)
            default:
                if alarmDepth > 0 {
                    if property.name == "TRIGGER" {
                        alarmTriggers.append(property.value)
                    }
                } else {
                    properties?.append(property)
                }
            }
        }
        return events
    }

    struct Property {
        let name: String
        let parameters: [String: String]
        let value: String

        init?(line: String) {
            // The value starts after the first colon that is not inside a
            // quoted parameter value.
            var inQuotes = false
            var colonIndex: String.Index?
            for index in line.indices {
                let character = line[index]
                if character == "\"" {
                    inQuotes.toggle()
                } else if character == ":", !inQuotes {
                    colonIndex = index
                    break
                }
            }
            guard let colonIndex else {
                return nil
            }
            let head = line[..<colonIndex].split(separator: ";", omittingEmptySubsequences: false)
            guard let name = head.first, !name.isEmpty else {
                return nil
            }
            var parameters = [String: String]()
            for parameter in head.dropFirst() {
                let parts = parameter.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    parameters[parts[0].uppercased()] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            self.name = name.uppercased()
            self.parameters = parameters
            self.value = String(line[line.index(after: colonIndex)...])
        }
    }

    static func unfold(_ text: String) -> [String] {
        var lines = [String]()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var isEscaped = false
        for character in text {
            if isEscaped {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func event(from properties: [Property], alarmTriggers: [String], calendar: Calendar) -> IvyEvent? {
        func first(_ name: String) -> Property? {
            properties.first { $0.name == name }
        }
        guard let startProperty = first("DTSTART"), let start = parseDate(startProperty, calendar: calendar) else {
            return nil
        }
        let isAllDay = start.isDateOnly
        var endAt: Date
        if let endProperty = first("DTEND"), let end = parseDate(endProperty, calendar: calendar) {
            if isAllDay {
                // DTEND is the day after the last day.
                endAt = calendar.date(byAdding: .day, value: -1, to: end.date) ?? start.date
            } else {
                endAt = end.date
            }
        } else if let duration = first("DURATION").flatMap({ parseDuration($0.value) }) {
            endAt = isAllDay
                ? calendar.date(byAdding: .day, value: -1, to: start.date.addingTimeInterval(duration)) ?? start.date
                : start.date.addingTimeInterval(duration)
        } else {
            endAt = isAllDay ? start.date : start.date.addingTimeInterval(60 * 60)
        }
        endAt = max(endAt, start.date)

        let title = first("SUMMARY").map { unescape($0.value) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let alertMinutes = alarmTriggers.compactMap(parseDuration).map { Int((-$0 / 60).rounded()) }.filter { $0 >= 0 }.min()

        return IvyEvent(
            title: title.isEmpty ? IvyLocalizedString("EVENT_UNTITLED", comment: "Title of an imported event that has none.") : title,
            notes: first("DESCRIPTION").map { unescape($0.value) } ?? "",
            location: first("LOCATION").map { unescape($0.value) } ?? "",
            startAt: start.date,
            endAt: endAt,
            isAllDay: isAllDay,
            recurrence: first("RRULE").flatMap { parseRule($0.value, start: start.date, calendar: calendar) },
            alertMinutes: alertMinutes,
            importedUID: first("UID").map { unescape($0.value) },
        )
    }

    struct ParsedDate {
        let date: Date
        let isDateOnly: Bool
    }

    static func parseDate(_ property: Property, calendar: Calendar) -> ParsedDate? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        if property.parameters["VALUE"]?.uppercased() == "DATE" || value.count == 8 {
            guard
                value.count >= 8,
                let year = Int(value.prefix(4)),
                let month = Int(value.dropFirst(4).prefix(2)),
                let day = Int(value.dropFirst(6).prefix(2)),
                let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
            else {
                return nil
            }
            return ParsedDate(date: date, isDateOnly: true)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            formatter.timeZone = property.parameters["TZID"].flatMap(timeZone(named:)) ?? calendar.timeZone
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return formatter.date(from: value).map { ParsedDate(date: $0, isDateOnly: false) }
    }

    /// Time zone names as calendar apps write them, like "Europe/Berlin" or
    /// "/Europe/Berlin".
    private static func timeZone(named name: String) -> TimeZone? {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "/\""))
        return TimeZone(identifier: trimmed) ?? TimeZone(abbreviation: trimmed)
    }

    /// Durations like "PT15M", "-P1D" or "P1W", in seconds.
    static func parseDuration(_ value: String) -> TimeInterval? {
        var text = value.trimmingCharacters(in: .whitespaces).uppercased()
        var sign: Double = 1
        if text.hasPrefix("-") {
            sign = -1
            text.removeFirst()
        } else if text.hasPrefix("+") {
            text.removeFirst()
        }
        guard text.hasPrefix("P") else {
            return nil
        }
        text.removeFirst()
        var seconds: Double = 0
        var number = ""
        var inTime = false
        var foundAny = false
        for character in text {
            if character.isNumber {
                number.append(character)
                continue
            }
            if character == "T" {
                inTime = true
                continue
            }
            guard let amount = Double(number) else {
                return nil
            }
            number = ""
            foundAny = true
            switch (character, inTime) {
            case ("W", false): seconds += amount * 7 * 86_400
            case ("D", false): seconds += amount * 86_400
            case ("H", true): seconds += amount * 3600
            case ("M", true): seconds += amount * 60
            case ("S", true): seconds += amount
            default: return nil
            }
        }
        return foundAny ? sign * seconds : nil
    }

    static func parseRule(_ value: String, start: Date, calendar: Calendar) -> IvyRecurrence? {
        var parts = [String: String]()
        for part in value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                parts[pair[0].uppercased()] = String(pair[1])
            }
        }
        guard let frequency = parts["FREQ"].flatMap({ IvyRecurrence.Frequency(rawValue: $0.lowercased()) }) else {
            return nil
        }
        let interval = parts["INTERVAL"].flatMap(Int.init) ?? 1
        var until: Date?
        if let untilValue = parts["UNTIL"] {
            let property = Property(line: "UNTIL:" + untilValue)
            until = property.flatMap { parseDate($0, calendar: calendar) }.map { parsed in
                // A date-only UNTIL includes that whole day.
                parsed.isDateOnly ? (calendar.date(byAdding: .second, value: 86_399, to: parsed.date) ?? parsed.date) : parsed.date
            }
        } else if let count = parts["COUNT"].flatMap(Int.init), count > 0 {
            until = calendar.date(byAdding: frequency.component, value: (count - 1) * max(interval, 1), to: start)
        }
        return IvyRecurrence(frequency: frequency, interval: interval, until: until)
    }
}
