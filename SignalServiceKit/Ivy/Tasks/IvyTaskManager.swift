//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Keeps tasks working on this device: schedules their notifications and
/// removes the link to a message when the message goes away (see
/// `IvyMessageLinks`).
public final class IvyTaskManager {

    public static let shared = IvyTaskManager()

    /// Posted on the main thread when tasks or task lists changed.
    public static let tasksDidChange = Notification.Name("IvyTasksDidChange")

    private var isStarted = false

    private var store: IvyDataStore? { IvyData.shared?.store }

    // MARK: - Lifecycle

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
        guard
            let kinds = notification.userInfo?["kinds"] as? Set<String>,
            kinds.contains(IvyTaskStore.taskKind) || kinds.contains(IvyTaskStore.listKind)
        else {
            return
        }
        refresh()
    }

    /// Reschedules notifications and tells the screens that show tasks.
    public func refresh() {
        AssertIsOnMainThread()
        let tasks = IvyTaskStore.all(store: store)
        updateSourceTimestamps(tasks)
        let listNames = Dictionary(uniqueKeysWithValues: IvyTaskStore.lists(store: store).map { ($0.id, $0.name) })
        Task {
            await IvyTaskNotifications.reschedule(tasks, listNames: listNames)
        }
        NotificationCenter.default.post(name: Self.tasksDidChange, object: nil)
    }

    // MARK: - Reading

    public func allTasks() -> [IvyTask] {
        return IvyTaskStore.all(store: store)
    }

    public func task(id: String) -> IvyTask? {
        return IvyTaskStore.task(id: id, store: store)
    }

    public func lists() -> [IvyTaskList] {
        return IvyTaskStore.lists(store: store)
    }

    // MARK: - Changing tasks

    public func save(_ task: IvyTask) {
        IvyTaskStore.save(task, store: store)
        refresh()
    }

    public func setDone(id: String, _ done: Bool) {
        guard var task = task(id: id) else {
            return
        }
        task.setDone(done)
        save(task)
    }

    /// Moves a task's due date to tomorrow, keeping its time of day.
    public func moveToTomorrow(id: String, calendar: Calendar = .current) {
        guard var task = task(id: id) else {
            return
        }
        let base = task.dueAt ?? calendar.date(bySettingHour: IvyTask.allDayReminderHour, minute: 0, second: 0, of: Date())
        guard
            let base,
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())),
            let dueAt = calendar.date(
                bySettingHour: calendar.component(.hour, from: base),
                minute: calendar.component(.minute, from: base),
                second: 0,
                of: tomorrow,
            )
        else {
            return
        }
        task.dueAt = task.isAllDay ? tomorrow : dueAt
        task.setDone(false)
        save(task)
    }

    public func delete(id: String) {
        IvyTaskStore.delete(id: id, store: store)
        refresh()
    }

    public func save(_ list: IvyTaskList) {
        IvyTaskStore.save(list, store: store)
        refresh()
    }

    public func delete(list: IvyTaskList) {
        IvyTaskStore.delete(list: list, store: store)
        refresh()
    }

    // MARK: - Messages that go away

    /// Timestamps of the messages that tasks link to. Checked first, because
    /// deleting a chat removes many messages at once.
    private let sourceLock = NSLock()
    private var sourceTimestamps: Set<UInt64>?

    private func updateSourceTimestamps(_ tasks: [IvyTask]) {
        let timestamps = Set(tasks.compactMap { $0.source?.message.timestamp })
        sourceLock.lock()
        sourceTimestamps = timestamps
        sourceLock.unlock()
    }

    func linksToMessage(timestamp: UInt64) -> Bool {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        // Nil until `start()`, which the main app calls at launch; tests and
        // extensions don't keep tasks.
        return sourceTimestamps?.contains(timestamp) == true
    }

    func removeSources(_ messages: Set<IvyMessageReference>) {
        let changed = IvyTaskStore.removeSources(messages, store: store)
        if !changed.isEmpty {
            refresh()
        }
    }
}
