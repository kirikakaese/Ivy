//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit
import WidgetKit

/// Keeps the glance file for widgets and the Mac menu bar up to date.
@MainActor
final class IvyGlanceWriter {

    static let shared = IvyGlanceWriter()

    private var isStarted = false
    private var pendingWrite: DispatchWorkItem?
    private var unreadCount = 0
    private var lastGlance: IvyGlance?

    /// Called when the app is ready and whenever it becomes active.
    func start() {
        if !isStarted {
            isStarted = true
            let center = NotificationCenter.default
            for name in [
                IvyTaskManager.tasksDidChange,
                IvyEventManager.eventsDidChange,
                IvyReminderManager.remindersDidChange,
                UIApplication.significantTimeChangeNotification,
            ] {
                center.addObserver(self, selector: #selector(somethingChanged), name: name, object: nil)
            }
            AppEnvironment.shared.badgeManager.addObserver(self)
        }
        scheduleWrite()
    }

    @objc
    private nonisolated func somethingChanged() {
        Task { @MainActor [weak self] in self?.scheduleWrite() }
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.write() }
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func write() {
        let reminders = IvyReminderManager.shared.openReminders()
        let chatNames = SSKEnvironment.shared.databaseStorageRef.read { tx in
            var names = [IvyChatReference: String]()
            for reminder in reminders where names[reminder.chat] == nil {
                if let thread = reminder.chat.thread(tx: tx) {
                    names[reminder.chat] = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, transaction: tx)
                }
            }
            return names
        }
        let defaultReminderTitle = IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
        let glance = Self.glance(
            events: IvyEventManager.shared.allEvents(),
            tasks: IvyTaskManager.shared.allTasks(),
            reminders: reminders,
            reminderTitle: { chatNames[$0.chat] ?? defaultReminderTitle },
            unreadCount: unreadCount,
            now: Date(),
        )
        // Only the time it was made changed: nothing to tell.
        var unchanged = lastGlance
        unchanged?.writtenAt = glance.writtenAt
        if unchanged == glance, Calendar.current.isDate(lastGlance?.writtenAt ?? .distantPast, inSameDayAs: glance.writtenAt) {
            return
        }
        lastGlance = glance
        IvyMenuBar.shared.update(glance)
        guard
            let url = IvyGlance.fileURL(appGroup: TSConstants.applicationGroup),
            let data = glance.encoded()
        else {
            return
        }
        do {
            // Widgets read it while the device is locked.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger.warn("Couldn't write the glance: \(error)")
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func glance(
        events: [IvyEvent],
        tasks: [IvyTask],
        reminders: [IvyReminder],
        reminderTitle: (IvyReminder) -> String,
        unreadCount: Int,
        now: Date,
        calendar: Calendar = .current,
    ) -> IvyGlance {
        let day = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        let dueToday = tasks.filter { task in
            guard !task.isDone, let dueAt = task.dueAt else { return false }
            return day.contains(dueAt)
        }
        let today = IvyCalendar.items(events: events, tasks: dueToday, reminders: reminders, in: day, calendar: calendar).compactMap { item -> IvyGlance.Item? in
            switch item.kind {
            case .event(let event):
                return IvyGlance.Item(
                    id: event.id,
                    kind: .event,
                    title: event.title,
                    start: item.start,
                    end: item.end,
                    isAllDay: item.isAllDay,
                    link: IvyLink.event(id: event.id).url,
                )
            case .task(let task):
                return IvyGlance.Item(
                    id: task.id,
                    kind: .task,
                    title: task.title,
                    start: item.start,
                    end: item.start,
                    isAllDay: item.isAllDay,
                    link: IvyLink.task(id: task.id).url,
                )
            case .reminder(let reminder):
                return IvyGlance.Item(
                    id: reminder.id,
                    kind: .reminder,
                    title: reminderTitle(reminder),
                    start: item.start,
                    end: item.start,
                    isAllDay: false,
                    link: IvyLink.home.url,
                )
            }
        }
        let open = tasks.filter { !$0.isDone }.sorted(by: IvyTask.areInIncreasingOrder)
        return IvyGlance(
            writtenAt: now,
            unreadCount: unreadCount,
            today: today,
            tasks: open.map { task in
                IvyGlance.Item(
                    id: task.id,
                    kind: .task,
                    title: task.title,
                    start: task.dueAt,
                    end: task.dueAt,
                    isAllDay: task.isAllDay,
                    link: IvyLink.task(id: task.id).url,
                )
            },
            openTaskCount: open.count,
        )
    }
}

extension IvyGlanceWriter: BadgeObserver {
    nonisolated func didUpdateBadgeCount(_ badgeManager: BadgeManager, badgeCount: BadgeCount) {
        let count = Int(badgeCount.unreadTotalCount)
        Task { @MainActor [weak self] in
            guard let self, self.unreadCount != count else { return }
            self.unreadCount = count
            self.scheduleWrite()
        }
    }
}
