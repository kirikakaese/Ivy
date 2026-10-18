//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A private to-do, made from a message or from scratch. Tasks are never sent
/// to chat partners; they sync only between the user's own Ivy devices.
public struct IvyTask: Equatable, Identifiable, Sendable {

    public enum Priority: Int, CaseIterable, Codable, Comparable, Sendable {
        case none = 0
        case low
        case medium
        case high

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct Subtask: Equatable, Codable, Identifiable, Sendable {
        public let id: String
        public var title: String
        public var isDone: Bool

        public init(id: String = UUID().uuidString, title: String, isDone: Bool = false) {
            self.id = id
            self.title = title
            self.isDone = isDone
        }
    }

    /// The message a task was made from. Removed when the message is
    /// deleted or disappears; the task itself stays.
    public struct Source: Equatable, Codable, Sendable {
        public let message: IvyMessageReference
        /// The message text when the task was made.
        public let quote: String

        public init(message: IvyMessageReference, quote: String) {
            self.message = message
            self.quote = quote
        }
    }

    /// Where a task belongs in the task list.
    public enum Group: Int, CaseIterable, Sendable {
        case overdue
        case today
        case upcoming
        case someday
        case done
    }

    public let id: String
    public var title: String
    public var notes: String
    public var dueAt: Date?
    /// A due date without a time; `dueAt` is then the start of that day.
    public var isAllDay: Bool
    /// Whether this device notifies when the task is due.
    public var reminds: Bool
    public var listId: String?
    public var priority: Priority
    public var subtasks: [Subtask]
    public var source: Source?
    public var isDone: Bool
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        dueAt: Date? = nil,
        isAllDay: Bool = false,
        reminds: Bool = false,
        listId: String? = nil,
        priority: Priority = .none,
        subtasks: [Subtask] = [],
        source: Source? = nil,
        isDone: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date(),
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.isAllDay = isAllDay
        self.reminds = reminds
        self.listId = listId
        self.priority = priority
        self.subtasks = subtasks
        self.source = source
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    /// An all-day task reminds in the morning of its day.
    public static let allDayReminderHour = 9

    /// When this task's notification is due, if it has one.
    public func reminderDate(calendar: Calendar = .current) -> Date? {
        guard reminds, !isDone, let dueAt else {
            return nil
        }
        guard isAllDay else {
            return dueAt
        }
        return calendar.date(bySettingHour: Self.allDayReminderHour, minute: 0, second: 0, of: dueAt)
    }

    public func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !isDone, let dueAt else {
            return false
        }
        if isAllDay {
            return calendar.startOfDay(for: dueAt) < calendar.startOfDay(for: now)
        }
        return dueAt < now
    }

    public func group(at now: Date, calendar: Calendar = .current) -> Group {
        if isDone {
            return .done
        }
        guard let dueAt else {
            return .someday
        }
        if isOverdue(at: now, calendar: calendar) {
            return .overdue
        }
        return calendar.isDate(dueAt, inSameDayAs: now) ? .today : .upcoming
    }

    /// Done subtasks and all subtasks, for "2/5".
    public var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    /// Marks the task done or open again.
    public mutating func setDone(_ done: Bool, at now: Date = Date()) {
        isDone = done
        completedAt = done ? now : nil
    }

    // MARK: - From a message

    static let maxTitleLength = 120
    static let maxQuoteLength = 500

    /// A title for a task made from a message: its first line of text.
    public static func title(fromMessageText text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return truncated(firstLine, to: maxTitleLength)
    }

    /// The part of a message's text that the task keeps.
    public static func quote(fromMessageText text: String) -> String {
        return truncated(text.trimmingCharacters(in: .whitespacesAndNewlines), to: maxQuoteLength)
    }

    private static func truncated(_ text: String, to length: Int) -> String {
        guard text.count > length else {
            return text
        }
        return String(text.prefix(length - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Order

    /// The order within a group: due date, then priority, then newest first.
    /// Done tasks: most recently completed first.
    public static func areInIncreasingOrder(_ lhs: IvyTask, _ rhs: IvyTask) -> Bool {
        if lhs.isDone, rhs.isDone {
            return (lhs.completedAt ?? .distantPast, lhs.id) > (rhs.completedAt ?? .distantPast, rhs.id)
        }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        return (lhs.createdAt, lhs.id) > (rhs.createdAt, rhs.id)
    }
}

/// A list that tasks can belong to, like "Work" or "Shopping".
public struct IvyTaskList: Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Store

/// Tasks and task lists in the Ivy data store.
public enum IvyTaskStore {

    static let taskKind = "task"
    static let listKind = "taskList"

    private enum Field {
        static let title = "title"
        static let notes = "notes"
        static let dueAt = "dueAt"
        static let isAllDay = "allDay"
        static let reminds = "reminds"
        static let listId = "list"
        static let priority = "priority"
        static let subtasks = "subtasks"
        static let source = "source"
        static let isDone = "done"
        static let completedAt = "completedAt"
        static let createdAt = "createdAt"
        static let name = "name"
    }

    // MARK: Tasks

    public static func all(store: IvyDataStore?) -> [IvyTask] {
        guard let store else {
            return []
        }
        return store.entities(kind: taskKind)
            .compactMap { id, fields in task(id: id, fields: fields) }
            .sorted(by: IvyTask.areInIncreasingOrder)
    }

    public static func task(id: String, store: IvyDataStore?) -> IvyTask? {
        return store?.entity(kind: taskKind, id: id).flatMap { task(id: id, fields: $0) }
    }

    /// Writes the fields that differ from the stored task, so edits on
    /// different devices to different fields don't overwrite each other.
    public static func save(_ task: IvyTask, store: IvyDataStore?) {
        let old = self.task(id: task.id, store: store)
        var fields = [String: String?]()
        func set<T: Encodable>(_ field: String, _ value: T?, changed: Bool) {
            if old == nil || changed {
                // `updateValue` keeps a nil value, which clears the field;
                // assigning nil through the subscript would drop the key.
                fields.updateValue(value.map { IvyDataStore.encode($0) }, forKey: field)
            }
        }
        set(Field.title, task.title, changed: old?.title != task.title)
        set(Field.notes, task.notes.nilIfEmpty, changed: old?.notes != task.notes)
        set(Field.dueAt, task.dueAt.map(millis), changed: old?.dueAt.map(millis) != task.dueAt.map(millis))
        set(Field.isAllDay, task.isAllDay, changed: old?.isAllDay != task.isAllDay)
        set(Field.reminds, task.reminds, changed: old?.reminds != task.reminds)
        set(Field.listId, task.listId, changed: old?.listId != task.listId)
        set(Field.priority, task.priority, changed: old?.priority != task.priority)
        set(Field.subtasks, task.subtasks.isEmpty ? nil : task.subtasks, changed: old?.subtasks != task.subtasks)
        set(Field.source, task.source, changed: old?.source != task.source)
        set(Field.isDone, task.isDone, changed: old?.isDone != task.isDone)
        set(
            Field.completedAt,
            task.completedAt.map(millis),
            changed: old?.completedAt.map(millis) != task.completedAt.map(millis),
        )
        set(Field.createdAt, millis(task.createdAt), changed: old.map { millis($0.createdAt) } != millis(task.createdAt))
        guard !fields.isEmpty else {
            return
        }
        store?.update(kind: taskKind, entityId: task.id, fields: fields)
    }

    public static func delete(id: String, store: IvyDataStore?) {
        store?.delete(kind: taskKind, entityId: id)
    }

    /// Removes the message link and quote from the tasks made from these
    /// messages. Returns the changed tasks.
    @discardableResult
    public static func removeSources(_ messages: Set<IvyMessageReference>, store: IvyDataStore?) -> [IvyTask] {
        guard !messages.isEmpty else {
            return []
        }
        var changed = [IvyTask]()
        for var task in all(store: store) {
            guard let source = task.source, messages.contains(source.message) else {
                continue
            }
            task.source = nil
            save(task, store: store)
            changed.append(task)
        }
        return changed
    }

    private static func task(id: String, fields: [String: String]) -> IvyTask? {
        guard let title = IvyDataStore.decode(String.self, from: fields[Field.title]) else {
            return nil
        }
        return IvyTask(
            id: id,
            title: title,
            notes: IvyDataStore.decode(String.self, from: fields[Field.notes]) ?? "",
            dueAt: IvyDataStore.decode(UInt64.self, from: fields[Field.dueAt]).map(date),
            isAllDay: IvyDataStore.decode(Bool.self, from: fields[Field.isAllDay]) ?? false,
            reminds: IvyDataStore.decode(Bool.self, from: fields[Field.reminds]) ?? false,
            listId: IvyDataStore.decode(String.self, from: fields[Field.listId]),
            priority: IvyDataStore.decode(IvyTask.Priority.self, from: fields[Field.priority]) ?? .none,
            subtasks: IvyDataStore.decode([IvyTask.Subtask].self, from: fields[Field.subtasks]) ?? [],
            source: IvyDataStore.decode(IvyTask.Source.self, from: fields[Field.source]),
            isDone: IvyDataStore.decode(Bool.self, from: fields[Field.isDone]) ?? false,
            completedAt: IvyDataStore.decode(UInt64.self, from: fields[Field.completedAt]).map(date),
            createdAt: IvyDataStore.decode(UInt64.self, from: fields[Field.createdAt]).map(date) ?? Date(timeIntervalSince1970: 0),
        )
    }

    // MARK: Lists

    public static func lists(store: IvyDataStore?) -> [IvyTaskList] {
        guard let store else {
            return []
        }
        return store.entities(kind: listKind)
            .compactMap { id, fields in
                IvyDataStore.decode(String.self, from: fields[Field.name]).map { IvyTaskList(id: id, name: $0) }
            }
            .sorted { ($0.name.localizedLowercase, $0.id) < ($1.name.localizedLowercase, $1.id) }
    }

    public static func save(_ list: IvyTaskList, store: IvyDataStore?) {
        store?.update(kind: listKind, entityId: list.id, fields: [Field.name: IvyDataStore.encode(list.name)])
    }

    /// Deletes a list. Its tasks stay, without a list.
    public static func delete(list: IvyTaskList, store: IvyDataStore?) {
        for var task in all(store: store) where task.listId == list.id {
            task.listId = nil
            save(task, store: store)
        }
        store?.delete(kind: listKind, entityId: list.id)
    }

    // MARK: Values

    private static func millis(_ date: Date) -> UInt64 {
        UInt64(max(date.timeIntervalSince1970, 0) * 1000)
    }

    private static func date(_ millis: UInt64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}
