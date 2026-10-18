//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UserNotifications

/// Keeps events working on this device: schedules their alerts.
public final class IvyEventManager {

    public static let shared = IvyEventManager()

    /// Posted on the main thread when events changed.
    public static let eventsDidChange = Notification.Name("IvyEventsDidChange")

    private var isStarted = false

    private var store: IvyDataStore? { IvyData.shared?.store }

    /// Called when the app is ready and whenever it becomes active.
    public func start() {
        AssertIsOnMainThread()
        if !isStarted {
            isStarted = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(dataDidChange(_:)),
                name: IvyDataStore.dataDidChange,
                object: nil,
            )
        }
        refresh()
    }

    @objc
    private func dataDidChange(_ notification: Notification) {
        guard let kinds = notification.userInfo?["kinds"] as? Set<String>, kinds.contains(IvyEventStore.kind) else {
            return
        }
        refresh()
    }

    public func refresh() {
        AssertIsOnMainThread()
        let events = IvyEventStore.all(store: store)
        updateSourceTimestamps(events)
        Task {
            await IvyEventNotifications.reschedule(events)
        }
        NotificationCenter.default.post(name: Self.eventsDidChange, object: nil)
    }

    public func allEvents() -> [IvyEvent] {
        return IvyEventStore.all(store: store)
    }

    public func event(id: String) -> IvyEvent? {
        return IvyEventStore.event(id: id, store: store)
    }

    public func save(_ event: IvyEvent) {
        IvyEventStore.save(event, store: store)
        refresh()
    }

    public func delete(id: String) {
        IvyEventStore.delete(id: id, store: store)
        refresh()
    }

    /// Imports the events of an `.ics` file.
    public func importCalendar(_ text: String) throws -> (added: Int, updated: Int) {
        let events = try IvyICS.parse(text)
        let result = IvyEventStore.importEvents(events, store: store)
        refresh()
        return result
    }

    // MARK: - Messages that go away

    private let sourceLock = NSLock()
    private var sourceTimestamps: Set<UInt64>?

    private func updateSourceTimestamps(_ events: [IvyEvent]) {
        let timestamps = Set(events.compactMap { $0.source?.message.timestamp })
        sourceLock.lock()
        sourceTimestamps = timestamps
        sourceLock.unlock()
    }

    func linksToMessage(timestamp: UInt64) -> Bool {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        return sourceTimestamps?.contains(timestamp) == true
    }

    func removeSources(_ messages: Set<IvyMessageReference>) {
        let changed = IvyEventStore.removeSources(messages, store: store)
        if !changed.isEmpty {
            refresh()
        }
    }
}

/// Removes the link and quote from tasks and events whose message goes away.
public enum IvyMessageLinks {

    /// Called when a message is deleted, disappears, or is deleted for
    /// everyone.
    public static func messageWillGoAway(_ message: TSMessage, tx: DBWriteTransaction) {
        let tasks = IvyTaskManager.shared
        let events = IvyEventManager.shared
        let linkedFromTask = tasks.linksToMessage(timestamp: message.timestamp)
        let linkedFromEvent = events.linksToMessage(timestamp: message.timestamp)
        guard
            linkedFromTask || linkedFromEvent,
            let thread = message.thread(tx: tx),
            let reference = IvyMessageReference(message: message, thread: thread)
        else {
            return
        }
        tx.addSyncCompletion {
            DispatchQueue.main.async {
                if linkedFromTask {
                    IvyTaskManager.shared.removeSources([reference])
                }
                if linkedFromEvent {
                    IvyEventManager.shared.removeSources([reference])
                }
            }
        }
    }
}

// MARK: - Notifications

/// Alerts for events. Only the next occurrence of each event is scheduled,
/// and only the soonest ones, because the system keeps a limited number of
/// pending notifications per app.
public enum IvyEventNotifications {

    public static let categoryIdentifier = "Ivy.event"
    static let identifierPrefix = "ivy-event-"
    public static let eventIdKey = "Ivy.eventId"

    /// At most this many event alerts are pending at a time.
    static let maxScheduled = 24

    public static var categories: Set<UNNotificationCategory> {
        [UNNotificationCategory(identifier: categoryIdentifier, actions: [], intentIdentifiers: [], options: [])]
    }

    public static func isEvent(_ request: UNNotificationRequest) -> Bool {
        request.content.categoryIdentifier == categoryIdentifier
    }

    public static func eventId(of request: UNNotificationRequest) -> String? {
        guard isEvent(request) else {
            return nil
        }
        return request.content.userInfo[eventIdKey] as? String
    }

    /// The soonest alerts after `now`: event, occurrence start and alert date.
    public static func scheduled(_ events: [IvyEvent], after now: Date, calendar: Calendar = .current) -> [(event: IvyEvent, start: Date, alertAt: Date)] {
        var result = [(event: IvyEvent, start: Date, alertAt: Date)]()
        for event in events {
            guard let minutes = event.alertMinutes else {
                continue
            }
            let lead = TimeInterval(minutes * 60)
            // The first occurrence whose alert is still ahead.
            guard let start = event.nextStart(onOrAfter: now.addingTimeInterval(lead), calendar: calendar) else {
                continue
            }
            var alertAt = start.addingTimeInterval(-lead)
            if event.isAllDay, minutes == 0 {
                alertAt = calendar.date(bySettingHour: IvyTask.allDayReminderHour, minute: 0, second: 0, of: start) ?? start
            }
            if alertAt > now {
                result.append((event, start, alertAt))
            }
        }
        return Array(result.sorted { $0.alertAt < $1.alertAt }.prefix(maxScheduled))
    }

    static func reschedule(_ events: [IvyEvent]) async {
        let center = UNUserNotificationCenter.current()
        let wanted = scheduled(events, after: Date())
        let wantedIds = Set(wanted.map { identifierPrefix + $0.event.id })
        let pending = await center.pendingNotificationRequests().filter(isEvent)
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !wantedIds.contains($0) })

        let timeFormatter = DateFormatter()
        timeFormatter.doesRelativeDateFormatting = true
        timeFormatter.dateStyle = .medium
        for (event, start, alertAt) in wanted {
            timeFormatter.timeStyle = event.isAllDay ? .none : .short
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = [timeFormatter.string(from: start), event.location].filter { !$0.isEmpty }.joined(separator: " · ")
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.threadIdentifier = categoryIdentifier
            content.userInfo = [eventIdKey: event.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(alertAt.timeIntervalSinceNow, 1), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: identifierPrefix + event.id, content: content, trigger: trigger))
            } catch {
                Logger.warn("Couldn't schedule an event alert: \(error)")
            }
        }
    }
}
