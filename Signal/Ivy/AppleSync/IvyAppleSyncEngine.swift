//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import EventKit
import SignalServiceKit
import UIKit

/// Syncs events with a calendar named Ivy in Apple Calendar, and tasks with
/// a list named Ivy in Apple Reminders, as chosen in the settings.
@MainActor
final class IvyAppleSyncEngine {

    static let shared = IvyAppleSyncEngine()

    private var eventStore = EKEventStore()
    private var isStarted = false
    private var isSyncing = false
    private var needsAnotherPass = false
    private var pendingSync: DispatchWorkItem?
    /// Apple tells about Ivy's own changes too; those don't need a sync.
    private var lastOwnChange = Date.distantPast

    private var databaseStorage: SDSDatabaseStorage { SSKEnvironment.shared.databaseStorageRef }

    // MARK: - Lifecycle

    /// Called when the app is ready and whenever it becomes active.
    func start() {
        if !isStarted {
            isStarted = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(ivyChanged), name: IvyTaskManager.tasksDidChange, object: nil)
            center.addObserver(self, selector: #selector(ivyChanged), name: IvyEventManager.eventsDidChange, object: nil)
            center.addObserver(self, selector: #selector(appleChanged), name: .EKEventStoreChanged, object: nil)
        }
        scheduleSync()
    }

    @objc
    private nonisolated func ivyChanged() {
        Task { @MainActor [weak self] in self?.scheduleSync() }
    }

    @objc
    private nonisolated func appleChanged() {
        Task { @MainActor [weak self] in
            guard let self, Date().timeIntervalSince(self.lastOwnChange) > 3 else {
                return
            }
            self.scheduleSync()
        }
    }

    /// Syncs soon. Changes that come in quick succession sync once.
    func scheduleSync(after delay: TimeInterval = 1) {
        pendingSync?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.syncNow() }
        }
        pendingSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func syncNow() async {
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }
        isSyncing = true
        var passes = 0
        repeat {
            needsAnotherPass = false
            passes += 1
            for kind in IvyAppleSyncKind.allCases {
                await sync(kind)
            }
        } while needsAnotherPass && passes < 3
        isSyncing = false
    }

    // MARK: - Access

    static func entityType(_ kind: IvyAppleSyncKind) -> EKEntityType {
        switch kind {
        case .calendar: return .event
        case .reminders: return .reminder
        }
    }

    static func hasAccess(_ kind: IvyAppleSyncKind) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType(kind))
        if #available(iOS 17, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    /// Asks for access if needed. Returns whether Ivy has it.
    func requestAccess(_ kind: IvyAppleSyncKind) async -> Bool {
        if Self.hasAccess(kind) {
            return true
        }
        let granted: Bool
        do {
            if #available(iOS 17, *) {
                switch kind {
                case .calendar: granted = try await eventStore.requestFullAccessToEvents()
                case .reminders: granted = try await eventStore.requestFullAccessToReminders()
                }
            } else {
                granted = try await eventStore.requestAccess(to: Self.entityType(kind))
            }
        } catch {
            Logger.warn("Apple \(kind.rawValue) access failed: \(error)")
            return false
        }
        if granted {
            // A store created before access was granted sees nothing.
            eventStore = EKEventStore()
        }
        return granted
    }

    // MARK: - The Ivy calendar and list

    private static let containerTitle = "Ivy"

    /// The calendar or list Ivy syncs with, created if needed. `isNew` is
    /// true when there was none, or the user deleted it in Apple.
    private func container(_ kind: IvyAppleSyncKind) -> (calendar: EKCalendar, isNew: Bool)? {
        let storedId = databaseStorage.read { tx in IvyAppleSyncSettings.containerId(kind, tx: tx) }
        if let storedId, let calendar = eventStore.calendar(withIdentifier: storedId) {
            return (calendar, false)
        }
        let defaultCalendar: EKCalendar?
        switch kind {
        case .calendar: defaultCalendar = eventStore.defaultCalendarForNewEvents
        case .reminders: defaultCalendar = eventStore.defaultCalendarForNewReminders()
        }
        let sources = eventStore.sources
        guard
            let source = defaultCalendar?.source
                ?? sources.first(where: { $0.sourceType == .calDAV })
                ?? sources.first(where: { $0.sourceType == .local })
        else {
            Logger.warn("No account for an Ivy \(kind.rawValue) list")
            return nil
        }
        let calendar = EKCalendar(for: Self.entityType(kind), eventStore: eventStore)
        calendar.title = Self.containerTitle
        calendar.source = source
        calendar.cgColor = UIColor(red: 0.30, green: 0.66, blue: 0.45, alpha: 1).cgColor
        do {
            try eventStore.saveCalendar(calendar, commit: true)
        } catch {
            Logger.warn("Couldn't create the Ivy \(kind.rawValue) list: \(error)")
            return nil
        }
        databaseStorage.write { tx in IvyAppleSyncSettings.setContainerId(calendar.calendarIdentifier, kind, tx: tx) }
        return (calendar, true)
    }

    // MARK: - Syncing

    private func sync(_ kind: IvyAppleSyncKind) async {
        let (mode, storedLinks) = databaseStorage.read { tx in
            (IvyAppleSyncSettings.mode(kind, tx: tx), IvyAppleSyncSettings.links(kind, tx: tx))
        }
        guard mode != .off, Self.hasAccess(kind), let store = IvyData.shared?.store else {
            return
        }
        guard let container = container(kind) else {
            return
        }
        let calendar = container.calendar
        // A new list starts over: Ivy's items are copied into it and none
        // count as deleted in Apple.
        let links = container.isNew ? [:] : storedLinks

        let result: (links: [String: IvyAppleLink], ivyChanged: Bool, appleChanged: Bool)?
        switch kind {
        case .calendar:
            result = syncEvents(mode: mode, links: links, calendar: calendar, store: store)
        case .reminders:
            result = await syncReminders(mode: mode, links: links, calendar: calendar, store: store)
        }
        guard let result else {
            return
        }
        if result.appleChanged {
            lastOwnChange = Date()
        }
        databaseStorage.write { tx in
            // Unless sync was turned off meanwhile.
            if IvyAppleSyncSettings.mode(kind, tx: tx) != .off {
                IvyAppleSyncSettings.setLinks(result.links, kind, tx: tx)
            }
        }
        if result.ivyChanged {
            switch kind {
            case .calendar: IvyEventManager.shared.refresh()
            case .reminders: IvyTaskManager.shared.refresh()
            }
        }
    }

    private func syncEvents(
        mode: IvyAppleSyncMode,
        links: [String: IvyAppleLink],
        calendar: EKCalendar,
        store: IvyDataStore,
    ) -> (links: [String: IvyAppleLink], ivyChanged: Bool, appleChanged: Bool) {
        let gregorian = Calendar.current
        var appleItems = [String: EKEvent]()
        // Linked events, wherever they are in time…
        for link in links.values {
            if let event = eventStore.calendarItem(withIdentifier: link.appleId) as? EKEvent, Self.isIn(event, calendar) {
                appleItems[link.appleId] = event
            }
        }
        // …and events added in Apple, from a year ago to three years ahead.
        let now = Date()
        if
            mode == .twoWay,
            let from = gregorian.date(byAdding: .year, value: -1, to: now),
            let to = gregorian.date(byAdding: .year, value: 3, to: now)
        {
            let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: [calendar])
            for occurrence in eventStore.events(matching: predicate) where appleItems[occurrence.calendarItemIdentifier] == nil {
                // The first occurrence stands for a repeating event.
                let event = eventStore.calendarItem(withIdentifier: occurrence.calendarItemIdentifier) as? EKEvent ?? occurrence
                appleItems[occurrence.calendarItemIdentifier] = event
            }
        }

        let side = IvyAppleSyncSide<IvyEvent, EKEvent>(
            ivyItems: Dictionary(IvyEventStore.all(store: store).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            appleItems: appleItems,
            refetch: { [eventStore] in eventStore.calendarItem(withIdentifier: $0) as? EKEvent },
            ivyFingerprint: { IvyAppleEventFields($0).fingerprint },
            appleFingerprint: { Self.fields(of: $0, calendar: gregorian).fingerprint },
            newAppleItem: { [eventStore] in
                let event = EKEvent(eventStore: eventStore)
                event.calendar = calendar
                return event
            },
            writeApple: { Self.write(IvyAppleEventFields($0), to: $1) },
            saveApple: { [eventStore] in try eventStore.save($0, span: .futureEvents, commit: true) },
            removeApple: { [eventStore] in try eventStore.remove($0, span: .futureEvents, commit: true) },
            newIvyItem: { apple in
                let fields = Self.fields(of: apple, calendar: gregorian)
                let event = IvyEvent(title: fields.title, startAt: fields.startAt, endAt: fields.endAt, createdAt: apple.creationDate ?? Date())
                return fields.applied(to: event)
            },
            updateIvy: { Self.fields(of: $1, calendar: gregorian).applied(to: $0) },
            saveIvy: { IvyEventStore.save($0, store: store) },
            deleteIvy: { IvyEventStore.delete(id: $0, store: store) },
        )
        return side.run(mode: mode, links: links)
    }

    private func syncReminders(
        mode: IvyAppleSyncMode,
        links: [String: IvyAppleLink],
        calendar: EKCalendar,
        store: IvyDataStore,
    ) async -> (links: [String: IvyAppleLink], ivyChanged: Bool, appleChanged: Bool)? {
        let gregorian = Calendar.current
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let reminders: [EKReminder]? = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
        }
        guard let reminders else {
            // Without Apple's list, missing reminders would look deleted.
            Logger.warn("Couldn't read the Ivy reminders list")
            return nil
        }
        let side = IvyAppleSyncSide<IvyTask, EKReminder>(
            ivyItems: Dictionary(IvyTaskStore.all(store: store).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            appleItems: Dictionary(reminders.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { first, _ in first }),
            refetch: { [eventStore] in eventStore.calendarItem(withIdentifier: $0) as? EKReminder },
            ivyFingerprint: { IvyAppleReminderFields($0).fingerprint },
            appleFingerprint: { Self.fields(of: $0, calendar: gregorian).fingerprint },
            newAppleItem: { [eventStore] in
                let reminder = EKReminder(eventStore: eventStore)
                reminder.calendar = calendar
                return reminder
            },
            writeApple: { Self.write(IvyAppleReminderFields($0), to: $1, calendar: gregorian) },
            saveApple: { [eventStore] in try eventStore.save($0, commit: true) },
            removeApple: { [eventStore] in try eventStore.remove($0, commit: true) },
            newIvyItem: { apple in
                let fields = Self.fields(of: apple, calendar: gregorian)
                let task = IvyTask(title: fields.title, createdAt: apple.creationDate ?? Date())
                return fields.applied(to: task, now: apple.completionDate ?? Date())
            },
            updateIvy: { ivy, apple in
                Self.fields(of: apple, calendar: gregorian).applied(to: ivy, now: apple.completionDate ?? Date())
            },
            saveIvy: { IvyTaskStore.save($0, store: store) },
            deleteIvy: { IvyTaskStore.delete(id: $0, store: store) },
        )
        return side.run(mode: mode, links: links)
    }

    private static func isIn(_ item: EKCalendarItem, _ calendar: EKCalendar) -> Bool {
        item.calendar?.calendarIdentifier == calendar.calendarIdentifier
    }

    // MARK: - Converting

    static func fields(of event: EKEvent, calendar: Calendar) -> IvyAppleEventFields {
        let start = event.startDate ?? Date()
        var end = event.endDate ?? start
        if event.isAllDay {
            // Apple ends an all-day event at the end of its last day; Ivy
            // keeps the start of the last day.
            end = max(calendar.startOfDay(for: end.addingTimeInterval(-1)), calendar.startOfDay(for: start))
        }
        return IvyAppleEventFields(
            title: event.title ?? "",
            notes: event.notes ?? "",
            location: event.location ?? "",
            startAt: start,
            endAt: end,
            isAllDay: event.isAllDay,
            recurrence: event.recurrenceRules?.first.flatMap(recurrence(from:)),
        )
    }

    static func write(_ fields: IvyAppleEventFields, to event: EKEvent) {
        event.title = fields.title
        event.notes = fields.notes.isEmpty ? nil : fields.notes
        event.location = fields.location.isEmpty ? nil : fields.location
        event.isAllDay = fields.isAllDay
        event.startDate = fields.startAt
        event.endDate = fields.endAt
        event.recurrenceRules = fields.recurrence.map { [rule(from: $0)] }
    }

    static func recurrence(from rule: EKRecurrenceRule) -> IvyRecurrence? {
        let frequency: IvyRecurrence.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }
        return IvyRecurrence(frequency: frequency, interval: rule.interval, until: rule.recurrenceEnd?.endDate)
    }

    static func rule(from recurrence: IvyRecurrence) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch recurrence.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: recurrence.interval,
            end: recurrence.until.map { EKRecurrenceEnd(end: $0) },
        )
    }

    static func fields(of reminder: EKReminder, calendar: Calendar) -> IvyAppleReminderFields {
        var dueAt: Date?
        var isAllDay = false
        if let components = reminder.dueDateComponents {
            isAllDay = components.hour == nil
            var dateComponents = DateComponents()
            dateComponents.year = components.year
            dateComponents.month = components.month
            dateComponents.day = components.day
            if !isAllDay {
                dateComponents.hour = components.hour
                dateComponents.minute = components.minute
                dateComponents.timeZone = components.timeZone
            }
            // An all-day reminder is due on its day wherever the device is.
            dueAt = calendar.date(from: dateComponents)
        }
        return IvyAppleReminderFields(
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            dueAt: dueAt,
            isAllDay: isAllDay,
            priority: IvyAppleReminderFields.priority(fromApple: reminder.priority),
            isDone: reminder.isCompleted,
        )
    }

    static func write(_ fields: IvyAppleReminderFields, to reminder: EKReminder, calendar: Calendar) {
        reminder.title = fields.title
        reminder.notes = fields.notes.isEmpty ? nil : fields.notes
        reminder.priority = IvyAppleReminderFields.applePriority(fields.priority)
        if let dueAt = fields.dueAt {
            let units: Set<Calendar.Component> = fields.isAllDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute]
            var components = calendar.dateComponents(units, from: dueAt)
            components.timeZone = fields.isAllDay ? nil : calendar.timeZone
            reminder.dueDateComponents = components
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.isCompleted = fields.isDone
    }
}

/// One kind of item on both sides, and how to read and change it.
@MainActor
private struct IvyAppleSyncSide<IvyItem: Identifiable, AppleItem: EKCalendarItem> where IvyItem.ID == String {
    var ivyItems: [String: IvyItem]
    var appleItems: [String: AppleItem]
    /// Apple's stored version of an item, read again after saving it.
    var refetch: (String) -> AppleItem?
    var ivyFingerprint: (IvyItem) -> String
    var appleFingerprint: (AppleItem) -> String
    var newAppleItem: () -> AppleItem
    var writeApple: (IvyItem, AppleItem) -> Void
    var saveApple: (AppleItem) throws -> Void
    var removeApple: (AppleItem) throws -> Void
    var newIvyItem: (AppleItem) -> IvyItem
    var updateIvy: (IvyItem, AppleItem) -> IvyItem
    var saveIvy: (IvyItem) -> Void
    var deleteIvy: (String) -> Void

    /// Carries out the plan. Returns the new links and which side changed.
    func run(mode: IvyAppleSyncMode, links: [String: IvyAppleLink]) -> (links: [String: IvyAppleLink], ivyChanged: Bool, appleChanged: Bool) {
        var links = links
        var ivyChanged = false
        var appleChanged = false
        let actions = IvyAppleSync.plan(
            mode: mode,
            ivy: ivyItems.mapValues(ivyFingerprint),
            apple: appleItems.mapValues(appleFingerprint),
            links: links,
        )

        func link(_ ivy: IvyItem, _ apple: AppleItem) {
            // What Apple stored can differ slightly from what Ivy wrote; the
            // stored version is what the next sync compares with.
            let stored = refetch(apple.calendarItemIdentifier) ?? apple
            links[ivy.id] = IvyAppleLink(
                appleId: stored.calendarItemIdentifier,
                ivyFingerprint: ivyFingerprint(ivy),
                appleFingerprint: appleFingerprint(stored),
            )
        }

        for action in actions {
            do {
                switch action {
                case .createInApple(let ivyId):
                    guard let ivy = ivyItems[ivyId] else { continue }
                    let apple = newAppleItem()
                    writeApple(ivy, apple)
                    try saveApple(apple)
                    appleChanged = true
                    link(ivy, apple)
                case .updateApple(let ivyId, let appleId):
                    guard let ivy = ivyItems[ivyId], let apple = appleItems[appleId] else { continue }
                    writeApple(ivy, apple)
                    try saveApple(apple)
                    appleChanged = true
                    link(ivy, apple)
                case .deleteFromApple(let appleId):
                    if let apple = appleItems[appleId] {
                        try removeApple(apple)
                        appleChanged = true
                    }
                    links = links.filter { $0.value.appleId != appleId }
                case .createInIvy(let appleId):
                    guard let apple = appleItems[appleId] else { continue }
                    let ivy = newIvyItem(apple)
                    saveIvy(ivy)
                    ivyChanged = true
                    link(ivy, apple)
                case .updateIvy(let ivyId, let appleId):
                    guard let ivy = ivyItems[ivyId], let apple = appleItems[appleId] else { continue }
                    let updated = updateIvy(ivy, apple)
                    saveIvy(updated)
                    ivyChanged = true
                    link(updated, apple)
                case .deleteFromIvy(let ivyId):
                    deleteIvy(ivyId)
                    ivyChanged = true
                    links[ivyId] = nil
                case .forget(let ivyId):
                    links[ivyId] = nil
                }
            } catch {
                Logger.warn("Apple sync step failed: \(error)")
            }
        }
        return (links, ivyChanged, appleChanged)
    }
}
