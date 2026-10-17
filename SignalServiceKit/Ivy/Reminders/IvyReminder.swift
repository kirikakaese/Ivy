//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// "Remind me in…" for a message or a whole chat.
public struct IvyReminder: Equatable, Identifiable, Sendable {

    public enum Repeat: String, CaseIterable, Codable, Sendable {
        case never
        case daily
        case weekly
        case monthly
    }

    public let id: String
    public var chat: IvyChatReference
    /// Set for a reminder about one message; nil for the whole chat.
    public var message: IvyMessageReference?
    public var dueAt: Date
    public var repeats: Repeat
    public var isDone: Bool

    public init(
        id: String = UUID().uuidString,
        chat: IvyChatReference,
        message: IvyMessageReference? = nil,
        dueAt: Date,
        repeats: Repeat = .never,
        isDone: Bool = false,
    ) {
        self.id = id
        self.chat = chat
        self.message = message
        self.dueAt = dueAt
        self.repeats = repeats
        self.isDone = isDone
    }

    public func isDue(at now: Date) -> Bool {
        return !isDone && dueAt <= now
    }

    /// The next due date of a repeating reminder after `date`.
    public func nextDueDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let component: Calendar.Component
        switch repeats {
        case .never: return nil
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        var next = dueAt
        var steps = 0
        while next <= date, steps < 10_000 {
            guard let candidate = calendar.date(byAdding: component, value: 1, to: next) else {
                return nil
            }
            next = candidate
            steps += 1
        }
        return next
    }

    // MARK: - Presets

    public enum Preset: CaseIterable, Sendable {
        case twentyMinutes
        case oneHour
        case threeHours
        case laterToday
        case tonight
        case tomorrowMorning
        case nextWeek

        /// The due date for this preset, or nil when it doesn't apply now
        /// (for example "later today" late in the evening).
        public func dueDate(from now: Date, calendar: Calendar = .current) -> Date? {
            func today(hour: Int) -> Date? {
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)
            }
            switch self {
            case .twentyMinutes:
                return now.addingTimeInterval(20 * 60)
            case .oneHour:
                return now.addingTimeInterval(60 * 60)
            case .threeHours:
                return now.addingTimeInterval(3 * 60 * 60)
            case .laterToday:
                // Four hours from now, if that is still before tonight.
                let later = now.addingTimeInterval(4 * 60 * 60)
                guard let tonight = today(hour: 20), later < tonight, calendar.isDate(later, inSameDayAs: now) else {
                    return nil
                }
                return later
            case .tonight:
                guard let tonight = today(hour: 20), tonight > now.addingTimeInterval(30 * 60) else {
                    return nil
                }
                return tonight
            case .tomorrowMorning:
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
                return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
            case .nextWeek:
                // Monday 8:00.
                var components = DateComponents()
                components.weekday = 2
                components.hour = 8
                return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
            }
        }
    }
}

// MARK: - Store

/// Reminders in the Ivy data store. They sync to all Ivy devices; each
/// device notifies once, and handling a reminder on one device marks it done
/// everywhere.
public enum IvyReminderStore {

    static let kind = "reminder"

    private enum Field {
        static let chat = "chat"
        static let message = "message"
        static let dueAt = "dueAt"
        static let repeats = "repeat"
        static let isDone = "done"
    }

    public static func all(store: IvyDataStore?) -> [IvyReminder] {
        guard let store else {
            return []
        }
        return store.entities(kind: kind).compactMap { id, fields in reminder(id: id, fields: fields) }
            .sorted { ($0.dueAt, $0.id) < ($1.dueAt, $1.id) }
    }

    public static func reminder(id: String, store: IvyDataStore?) -> IvyReminder? {
        return store?.entity(kind: kind, id: id).flatMap { reminder(id: id, fields: $0) }
    }

    /// Open reminders, soonest first.
    public static func open(store: IvyDataStore?) -> [IvyReminder] {
        return all(store: store).filter { !$0.isDone }
    }

    public static func save(_ reminder: IvyReminder, store: IvyDataStore?) {
        let old = self.reminder(id: reminder.id, store: store)
        var fields = [String: String?]()
        if old?.chat != reminder.chat {
            fields[Field.chat] = IvyDataStore.encode(reminder.chat)
        }
        if old?.message != reminder.message || old == nil {
            fields[Field.message] = reminder.message.map { IvyDataStore.encode($0) }
        }
        if old?.dueAt != reminder.dueAt {
            fields[Field.dueAt] = IvyDataStore.encode(UInt64(reminder.dueAt.timeIntervalSince1970 * 1000))
        }
        if old?.repeats != reminder.repeats {
            fields[Field.repeats] = IvyDataStore.encode(reminder.repeats)
        }
        if old?.isDone != reminder.isDone {
            fields[Field.isDone] = IvyDataStore.encode(reminder.isDone)
        }
        guard !fields.isEmpty else {
            return
        }
        store?.update(kind: kind, entityId: reminder.id, fields: fields)
    }

    public static func delete(id: String, store: IvyDataStore?) {
        store?.delete(kind: kind, entityId: id)
    }

    private static func reminder(id: String, fields: [String: String]) -> IvyReminder? {
        guard
            let chat = IvyDataStore.decode(IvyChatReference.self, from: fields[Field.chat]),
            let dueAtMillis = IvyDataStore.decode(UInt64.self, from: fields[Field.dueAt])
        else {
            return nil
        }
        return IvyReminder(
            id: id,
            chat: chat,
            message: IvyDataStore.decode(IvyMessageReference.self, from: fields[Field.message]),
            dueAt: Date(timeIntervalSince1970: TimeInterval(dueAtMillis) / 1000),
            repeats: IvyDataStore.decode(IvyReminder.Repeat.self, from: fields[Field.repeats]) ?? .never,
            isDone: IvyDataStore.decode(Bool.self, from: fields[Field.isDone]) ?? false,
        )
    }
}
