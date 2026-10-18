//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A calendar event, made from a message, from scratch or from an imported
/// `.ics` file. Like tasks, events are private and sync only between the
/// user's own Ivy devices.
public struct IvyEvent: Equatable, Identifiable, Sendable {

    public let id: String
    public var title: String
    public var notes: String
    public var location: String
    public var startAt: Date
    /// For an all-day event, the start of its last day.
    public var endAt: Date
    public var isAllDay: Bool
    public var recurrence: IvyRecurrence?
    /// Minutes before the start when this device notifies; nil for none.
    public var alertMinutes: Int?
    public var source: IvyTask.Source?
    /// The UID of the imported calendar entry, so importing it again
    /// updates the event instead of adding a copy.
    public var importedUID: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        location: String = "",
        startAt: Date,
        endAt: Date,
        isAllDay: Bool = false,
        recurrence: IvyRecurrence? = nil,
        alertMinutes: Int? = nil,
        source: IvyTask.Source? = nil,
        importedUID: String? = nil,
        createdAt: Date = Date(),
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.location = location
        self.startAt = startAt
        self.endAt = max(endAt, startAt)
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.alertMinutes = alertMinutes
        self.source = source
        self.importedUID = importedUID
        self.createdAt = createdAt
    }

    /// How long one occurrence lasts. All-day events count whole days.
    public func duration(calendar: Calendar = .current) -> TimeInterval {
        if isAllDay {
            let lastDay = calendar.startOfDay(for: endAt)
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return end.timeIntervalSince(calendar.startOfDay(for: startAt))
        }
        return endAt.timeIntervalSince(startAt)
    }

    /// The start of every occurrence that overlaps `interval`.
    public func occurrences(in interval: DateInterval, calendar: Calendar = .current) -> [Date] {
        let length = duration(calendar: calendar)
        func overlaps(_ start: Date) -> Bool {
            let end = start.addingTimeInterval(max(length, 1))
            return start < interval.end && end > interval.start
        }
        guard let recurrence else {
            return overlaps(startAt) ? [startAt] : []
        }
        var result = [Date]()
        for start in recurrence.starts(from: startAt, calendar: calendar) {
            if start >= interval.end {
                break
            }
            if overlaps(start) {
                result.append(start)
            }
        }
        return result
    }

    /// The next occurrence that starts at or after `date`.
    public func nextStart(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        guard let recurrence else {
            return startAt >= date ? startAt : nil
        }
        return recurrence.starts(from: startAt, calendar: calendar).first { $0 >= date }
    }

    /// An event for the date found in a message, before the user edits it.
    public static func draft(from detected: IvyDetectedDate, title: String, source: IvyTask.Source?, calendar: Calendar = .current) -> IvyEvent {
        if detected.isAllDay {
            let day = calendar.startOfDay(for: detected.date)
            return IvyEvent(title: title, startAt: day, endAt: day, isAllDay: true, source: source)
        }
        let duration = detected.duration.flatMap { $0 > 0 ? $0 : nil } ?? 60 * 60
        return IvyEvent(title: title, startAt: detected.date, endAt: detected.date.addingTimeInterval(duration), source: source)
    }
}

/// How an event repeats.
public struct IvyRecurrence: Equatable, Codable, Sendable {

    public enum Frequency: String, CaseIterable, Codable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly

        var component: Calendar.Component {
            switch self {
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }

    public var frequency: Frequency
    public var interval: Int
    /// The last day an occurrence may start, if any.
    public var until: Date?

    public init(frequency: Frequency, interval: Int = 1, until: Date? = nil) {
        self.frequency = frequency
        self.interval = max(interval, 1)
        self.until = until
    }

    /// At most this many occurrences are computed, so a daily event over
    /// many years can't slow the calendar down.
    static let maxOccurrences = 3660

    /// Occurrence starts, counted from the first one so that monthly events
    /// on the 31st don't drift to the 28th.
    public func starts(from first: Date, calendar: Calendar = .current) -> AnySequence<Date> {
        let component = frequency.component
        let step = interval
        let until = self.until
        return AnySequence { () -> AnyIterator<Date> in
            var index = 0
            return AnyIterator {
                while index < Self.maxOccurrences {
                    defer { index += 1 }
                    guard let start = calendar.date(byAdding: component, value: index * step, to: first) else {
                        return nil
                    }
                    if let until, start > until {
                        return nil
                    }
                    // Skip months without the day, like 31 February.
                    if component == .month || component == .year,
                       calendar.component(.day, from: start) != calendar.component(.day, from: first)
                    {
                        continue
                    }
                    return start
                }
                return nil
            }
        }
    }
}

// MARK: - Store

/// Events in the Ivy data store.
public enum IvyEventStore {

    static let kind = "event"

    private enum Field {
        static let title = "title"
        static let notes = "notes"
        static let location = "location"
        static let startAt = "startAt"
        static let endAt = "endAt"
        static let isAllDay = "allDay"
        static let recurrence = "recurrence"
        static let alertMinutes = "alert"
        static let source = "source"
        static let importedUID = "uid"
        static let createdAt = "createdAt"
    }

    public static func all(store: IvyDataStore?) -> [IvyEvent] {
        guard let store else {
            return []
        }
        return store.entities(kind: kind)
            .compactMap { id, fields in event(id: id, fields: fields) }
            .sorted { ($0.startAt, $0.id) < ($1.startAt, $1.id) }
    }

    public static func event(id: String, store: IvyDataStore?) -> IvyEvent? {
        return store?.entity(kind: kind, id: id).flatMap { event(id: id, fields: $0) }
    }

    /// Writes the fields that differ from the stored event.
    public static func save(_ event: IvyEvent, store: IvyDataStore?) {
        let old = self.event(id: event.id, store: store)
        var fields = [String: String?]()
        func set<T: Encodable>(_ field: String, _ value: T?, changed: Bool) {
            if old == nil || changed {
                fields[field] = value.map { IvyDataStore.encode($0) }
            }
        }
        set(Field.title, event.title, changed: old?.title != event.title)
        set(Field.notes, event.notes.nilIfEmpty, changed: old?.notes != event.notes)
        set(Field.location, event.location.nilIfEmpty, changed: old?.location != event.location)
        set(Field.startAt, millis(event.startAt), changed: old.map { millis($0.startAt) } != millis(event.startAt))
        set(Field.endAt, millis(event.endAt), changed: old.map { millis($0.endAt) } != millis(event.endAt))
        set(Field.isAllDay, event.isAllDay, changed: old?.isAllDay != event.isAllDay)
        set(Field.recurrence, event.recurrence, changed: old?.recurrence != event.recurrence)
        set(Field.alertMinutes, event.alertMinutes, changed: old?.alertMinutes != event.alertMinutes)
        set(Field.source, event.source, changed: old?.source != event.source)
        set(Field.importedUID, event.importedUID, changed: old?.importedUID != event.importedUID)
        set(Field.createdAt, millis(event.createdAt), changed: old.map { millis($0.createdAt) } != millis(event.createdAt))
        guard !fields.isEmpty else {
            return
        }
        store?.update(kind: kind, entityId: event.id, fields: fields)
    }

    public static func delete(id: String, store: IvyDataStore?) {
        store?.delete(kind: kind, entityId: id)
    }

    /// Removes the message link and quote from events made from these
    /// messages. Returns the changed events.
    @discardableResult
    public static func removeSources(_ messages: Set<IvyMessageReference>, store: IvyDataStore?) -> [IvyEvent] {
        guard !messages.isEmpty else {
            return []
        }
        var changed = [IvyEvent]()
        for var event in all(store: store) {
            guard let source = event.source, messages.contains(source.message) else {
                continue
            }
            event.source = nil
            save(event, store: store)
            changed.append(event)
        }
        return changed
    }

    /// Adds imported events, or updates the ones imported before with the
    /// same UID. Returns how many were added and how many updated.
    public static func importEvents(_ events: [IvyEvent], store: IvyDataStore?) -> (added: Int, updated: Int) {
        var byUID = [String: IvyEvent]()
        for event in all(store: store) {
            if let uid = event.importedUID {
                byUID[uid] = event
            }
        }
        var added = 0
        var updated = 0
        for imported in events {
            if let uid = imported.importedUID, let existing = byUID[uid] {
                let changed = IvyEvent(
                    id: existing.id,
                    title: imported.title,
                    notes: imported.notes,
                    location: imported.location,
                    startAt: imported.startAt,
                    endAt: imported.endAt,
                    isAllDay: imported.isAllDay,
                    recurrence: imported.recurrence,
                    alertMinutes: imported.alertMinutes,
                    source: existing.source,
                    importedUID: uid,
                    createdAt: existing.createdAt,
                )
                if changed != existing {
                    save(changed, store: store)
                    updated += 1
                }
            } else {
                save(imported, store: store)
                added += 1
            }
        }
        return (added, updated)
    }

    private static func event(id: String, fields: [String: String]) -> IvyEvent? {
        guard
            let title = IvyDataStore.decode(String.self, from: fields[Field.title]),
            let startMillis = IvyDataStore.decode(UInt64.self, from: fields[Field.startAt])
        else {
            return nil
        }
        let startAt = date(startMillis)
        return IvyEvent(
            id: id,
            title: title,
            notes: IvyDataStore.decode(String.self, from: fields[Field.notes]) ?? "",
            location: IvyDataStore.decode(String.self, from: fields[Field.location]) ?? "",
            startAt: startAt,
            endAt: IvyDataStore.decode(UInt64.self, from: fields[Field.endAt]).map(date) ?? startAt,
            isAllDay: IvyDataStore.decode(Bool.self, from: fields[Field.isAllDay]) ?? false,
            recurrence: IvyDataStore.decode(IvyRecurrence.self, from: fields[Field.recurrence]),
            alertMinutes: IvyDataStore.decode(Int.self, from: fields[Field.alertMinutes]),
            source: IvyDataStore.decode(IvyTask.Source.self, from: fields[Field.source]),
            importedUID: IvyDataStore.decode(String.self, from: fields[Field.importedUID]),
            createdAt: IvyDataStore.decode(UInt64.self, from: fields[Field.createdAt]).map(date) ?? Date(timeIntervalSince1970: 0),
        )
    }

    private static func millis(_ date: Date) -> UInt64 {
        UInt64(max(date.timeIntervalSince1970, 0) * 1000)
    }

    private static func date(_ millis: UInt64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}
