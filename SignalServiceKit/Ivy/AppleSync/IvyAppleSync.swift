//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What Ivy keeps in Apple Calendar or Apple Reminders.
public enum IvyAppleSyncKind: String, CaseIterable, Sendable {
    /// Events, in a calendar named Ivy.
    case calendar
    /// Tasks, in a reminders list named Ivy.
    case reminders
}

/// How Ivy syncs with Apple Calendar or Apple Reminders on this device.
public enum IvyAppleSyncMode: String, CaseIterable, Sendable {
    case off
    /// Ivy copies its items to Apple. Changes made in Apple are replaced
    /// with Ivy's version.
    case copy
    /// Changes go both ways. When an item changed on both sides, Ivy's
    /// version wins.
    case twoWay
}

/// The Apple item an Ivy item is synced with, and what both looked like at
/// the last sync. The fingerprints tell which side changed since.
public struct IvyAppleLink: Codable, Equatable, Sendable {
    public var appleId: String
    public var ivyFingerprint: String
    public var appleFingerprint: String

    public init(appleId: String, ivyFingerprint: String, appleFingerprint: String) {
        self.appleId = appleId
        self.ivyFingerprint = ivyFingerprint
        self.appleFingerprint = appleFingerprint
    }
}

/// Apple sync settings and links. They stay on this device: Apple's item
/// identifiers are different on every device.
public enum IvyAppleSyncSettings {

    private static let store = KeyValueStore(collection: "IvyAppleSync")

    private static func key(_ name: String, _ kind: IvyAppleSyncKind) -> String {
        "\(kind.rawValue).\(name)"
    }

    public static func mode(_ kind: IvyAppleSyncKind, tx: DBReadTransaction) -> IvyAppleSyncMode {
        store.getString(key("mode", kind), transaction: tx).flatMap(IvyAppleSyncMode.init(rawValue:)) ?? .off
    }

    /// Turning sync off forgets the links, so turning it on again starts
    /// over with a fresh copy.
    public static func setMode(_ mode: IvyAppleSyncMode, _ kind: IvyAppleSyncKind, tx: DBWriteTransaction) {
        store.setString(mode.rawValue, key: key("mode", kind), transaction: tx)
        if mode == .off {
            setLinks([:], kind, tx: tx)
        }
    }

    /// The identifier of the Apple calendar or reminders list Ivy uses.
    public static func containerId(_ kind: IvyAppleSyncKind, tx: DBReadTransaction) -> String? {
        store.getString(key("container", kind), transaction: tx)
    }

    public static func setContainerId(_ id: String?, _ kind: IvyAppleSyncKind, tx: DBWriteTransaction) {
        store.setString(id, key: key("container", kind), transaction: tx)
    }

    /// Links by Ivy item id.
    public static func links(_ kind: IvyAppleSyncKind, tx: DBReadTransaction) -> [String: IvyAppleLink] {
        guard let data = store.getData(key("links", kind), transaction: tx) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: IvyAppleLink].self, from: data)) ?? [:]
    }

    public static func setLinks(_ links: [String: IvyAppleLink], _ kind: IvyAppleSyncKind, tx: DBWriteTransaction) {
        let data = links.isEmpty ? nil : (try? JSONEncoder().encode(links))
        store.setData(data, key: key("links", kind), transaction: tx)
    }
}

// MARK: - Fields

/// The parts of an event that Apple Calendar shows. Alerts stay in Ivy, so
/// they don't ring twice.
public struct IvyAppleEventFields: Codable, Equatable, Sendable {
    public var title: String
    public var notes: String
    public var location: String
    public var startAt: Date
    public var endAt: Date
    public var isAllDay: Bool
    public var recurrence: IvyRecurrence?

    public init(title: String, notes: String, location: String, startAt: Date, endAt: Date, isAllDay: Bool, recurrence: IvyRecurrence?) {
        self.title = title
        self.notes = notes
        self.location = location
        self.startAt = startAt
        self.endAt = endAt
        self.isAllDay = isAllDay
        self.recurrence = recurrence
    }

    public init(_ event: IvyEvent) {
        self.init(
            title: event.title,
            notes: event.notes,
            location: event.location,
            startAt: event.startAt,
            endAt: event.endAt,
            isAllDay: event.isAllDay,
            recurrence: event.recurrence,
        )
    }

    /// Returns `event` with these fields; the fields Apple doesn't show stay.
    public func applied(to event: IvyEvent) -> IvyEvent {
        var event = event
        event.title = title
        event.notes = notes
        event.location = location
        event.startAt = startAt
        event.endAt = max(endAt, startAt)
        event.isAllDay = isAllDay
        event.recurrence = recurrence
        return event
    }

    public var fingerprint: String { IvyAppleSync.fingerprint(self) }
}

/// The parts of a task that Apple Reminders shows. Subtasks, lists, the
/// linked message and reminders stay in Ivy.
public struct IvyAppleReminderFields: Codable, Equatable, Sendable {
    public var title: String
    public var notes: String
    public var dueAt: Date?
    public var isAllDay: Bool
    public var priority: IvyTask.Priority
    public var isDone: Bool

    public init(title: String, notes: String, dueAt: Date?, isAllDay: Bool, priority: IvyTask.Priority, isDone: Bool) {
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.isAllDay = dueAt != nil && isAllDay
        self.priority = priority
        self.isDone = isDone
    }

    public init(_ task: IvyTask) {
        self.init(title: task.title, notes: task.notes, dueAt: task.dueAt, isAllDay: task.isAllDay, priority: task.priority, isDone: task.isDone)
    }

    public func applied(to task: IvyTask, now: Date = Date()) -> IvyTask {
        var task = task
        task.title = title
        task.notes = notes
        task.dueAt = dueAt
        task.isAllDay = isAllDay
        task.priority = priority
        if task.isDone != isDone {
            task.setDone(isDone, at: now)
        }
        return task
    }

    public var fingerprint: String { IvyAppleSync.fingerprint(self) }

    /// Apple's priorities run from 1 (highest) to 9 (lowest); 0 is none.
    public static func priority(fromApple value: Int) -> IvyTask.Priority {
        switch value {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    public static func applePriority(_ priority: IvyTask.Priority) -> Int {
        switch priority {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }
}

// MARK: - Planning

public enum IvyAppleSync {

    /// What to do so both sides match.
    public enum Action: Equatable, Sendable {
        case createInApple(ivyId: String)
        case updateApple(ivyId: String, appleId: String)
        case deleteFromApple(appleId: String)
        case createInIvy(appleId: String)
        case updateIvy(ivyId: String, appleId: String)
        case deleteFromIvy(ivyId: String)
        /// Both sides are gone; only the link is left.
        case forget(ivyId: String)
    }

    /// Compares Ivy's items and Apple's items with the links from the last
    /// sync.
    ///
    /// - Parameters:
    ///   - ivy: Fingerprints of Ivy's items by Ivy id.
    ///   - apple: Fingerprints of the items in Ivy's Apple calendar or list
    ///     by Apple id.
    ///   - links: Links from the last sync by Ivy id.
    public static func plan(
        mode: IvyAppleSyncMode,
        ivy: [String: String],
        apple: [String: String],
        links: [String: IvyAppleLink],
    ) -> [Action] {
        guard mode != .off else {
            return []
        }
        var actions = [Action]()
        var linkedAppleIds = Set<String>()
        for (ivyId, link) in links.sorted(by: { $0.key < $1.key }) {
            linkedAppleIds.insert(link.appleId)
            switch (ivy[ivyId], apple[link.appleId]) {
            case (nil, nil):
                actions.append(.forget(ivyId: ivyId))
            case (nil, .some):
                actions.append(.deleteFromApple(appleId: link.appleId))
            case (.some, nil):
                // Deleted in Apple: two-way deletes it in Ivy too, a copy
                // puts it back.
                actions.append(mode == .twoWay ? .deleteFromIvy(ivyId: ivyId) : .createInApple(ivyId: ivyId))
            case let (ivyFingerprint?, appleFingerprint?):
                let ivyChanged = ivyFingerprint != link.ivyFingerprint
                let appleChanged = appleFingerprint != link.appleFingerprint
                if ivyChanged || (appleChanged && mode == .copy) {
                    actions.append(.updateApple(ivyId: ivyId, appleId: link.appleId))
                } else if appleChanged {
                    actions.append(.updateIvy(ivyId: ivyId, appleId: link.appleId))
                }
            }
        }
        for ivyId in ivy.keys.sorted() where links[ivyId] == nil {
            actions.append(.createInApple(ivyId: ivyId))
        }
        if mode == .twoWay {
            for appleId in apple.keys.sorted() where !linkedAppleIds.contains(appleId) {
                actions.append(.createInIvy(appleId: appleId))
            }
        }
        return actions
    }

    /// A stable text that changes whenever one of the fields changes. Dates
    /// count in whole seconds, because Apple drops fractions.
    static func fingerprint<T: Encodable>(_ fields: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64(date.timeIntervalSince1970.rounded(.down)))
        }
        guard let data = try? encoder.encode(fields) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }
}
