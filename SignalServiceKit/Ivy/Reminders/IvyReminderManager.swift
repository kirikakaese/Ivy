//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Keeps reminders working on this device: schedules their notifications,
/// marks a chat unread when its reminder comes due, and handles snooze and
/// done.
public final class IvyReminderManager {

    public static let shared = IvyReminderManager()

    /// Posted on the main thread when reminders changed or one came due.
    public static let remindersDidChange = Notification.Name("IvyRemindersDidChange")

    private var dueTimer: Timer?
    private var isStarted = false

    /// Due dates already handled on this device, by reminder id, so a chat is
    /// marked unread once per due date.
    private let firedStore = KeyValueStore(collection: "IvyReminderFired")

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
        guard let kinds = notification.userInfo?["kinds"] as? Set<String>, kinds.contains(IvyReminderStore.kind) else {
            return
        }
        refresh()
    }

    /// Fires due reminders, reschedules notifications and the timer.
    public func refresh() {
        AssertIsOnMainThread()
        let reminders = IvyReminderStore.all(store: store)
        updateMarkers(reminders)
        fireDueReminders(reminders)
        scheduleTimer(reminders)
        scheduleNotifications(reminders)
        NotificationCenter.default.post(name: Self.remindersDidChange, object: nil)
    }

    private func scheduleTimer(_ reminders: [IvyReminder]) {
        dueTimer?.invalidate()
        dueTimer = nil
        let now = Date()
        guard let next = reminders.filter({ !$0.isDone && $0.dueAt > now }).map(\.dueAt).min() else {
            return
        }
        dueTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.5, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    private func fireDueReminders(_ reminders: [IvyReminder]) {
        let now = Date()
        let due = reminders.filter { $0.isDue(at: now) }
        guard !due.isEmpty else {
            return
        }
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            for reminder in due {
                let dueMillis = Int64(reminder.dueAt.timeIntervalSince1970 * 1000)
                guard firedStore.getInt64(reminder.id, transaction: tx) != dueMillis else {
                    continue
                }
                firedStore.setInt64(dueMillis, key: reminder.id, transaction: tx)
                if let thread = reminder.chat.thread(tx: tx), !thread.isMarkedUnread {
                    thread.updateWith(isMarkedUnread: true, updateStorageService: true, transaction: tx)
                }
            }
        }
    }

    private func scheduleNotifications(_ reminders: [IvyReminder]) {
        var titles = [String: String]()
        var bodies = [String: String]()
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            for reminder in reminders where !reminder.isDone {
                let thread = reminder.chat.thread(tx: tx)
                titles[reminder.id] = thread.map { SSKEnvironment.shared.contactManagerRef.displayName(for: $0, transaction: tx) }
                    ?? IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.")
                bodies[reminder.id] = Self.body(for: reminder, tx: tx)
            }
        }
        Task {
            await IvyReminderNotifications.reschedule(reminders, titles: titles, bodies: bodies)
        }
    }

    /// The text of a reminder: the message, or a note that it's about the
    /// chat.
    public static func body(for reminder: IvyReminder, tx: DBReadTransaction) -> String {
        if let message = reminder.message?.message(tx: tx) {
            let text = message.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                return String(text.prefix(200))
            }
            return IvyLocalizedString("REMINDER_BODY_MESSAGE", comment: "Body of a reminder notification about a message without text.")
        }
        return IvyLocalizedString("REMINDER_BODY_CHAT", comment: "Body of a reminder notification about a whole chat.")
    }

    // MARK: - Changing reminders

    public func add(_ reminder: IvyReminder) {
        IvyReminderStore.save(reminder, store: store)
        refresh()
    }

    public func snooze(id: String, until date: Date) {
        guard var reminder = IvyReminderStore.reminder(id: id, store: store) else {
            return
        }
        reminder.dueAt = date
        reminder.isDone = false
        IvyReminderStore.save(reminder, store: store)
        refresh()
    }

    public func snoozeOneHour(id: String) {
        snooze(id: id, until: Date().addingTimeInterval(60 * 60))
    }

    public func remindTomorrow(id: String) {
        guard let date = IvyReminder.Preset.tomorrowMorning.dueDate(from: Date()) else {
            return
        }
        snooze(id: id, until: date)
    }

    /// Marks a reminder done. A repeating reminder moves to its next date.
    public func markDone(id: String) {
        guard var reminder = IvyReminderStore.reminder(id: id, store: store) else {
            return
        }
        if let next = reminder.nextDueDate(after: Date()) {
            reminder.dueAt = next
        } else {
            reminder.isDone = true
        }
        IvyReminderStore.save(reminder, store: store)
        refresh()
    }

    public func delete(id: String) {
        IvyReminderStore.delete(id: id, store: store)
        refresh()
    }

    /// Marks the due reminders of a chat done, when the user opens it from
    /// the reminder.
    public func markDueRemindersDone(chat: IvyChatReference) {
        let now = Date()
        for reminder in IvyReminderStore.open(store: store) where reminder.chat == chat && reminder.isDue(at: now) {
            markDone(id: reminder.id)
        }
    }

    // MARK: - Markers

    private let markerLock = NSLock()
    private var chatMarkers = Set<IvyChatReference>()
    private var messageMarkers = Set<IvyMessageReference>()

    private func updateMarkers(_ reminders: [IvyReminder]) {
        let open = reminders.filter { !$0.isDone }
        let newChats = Set(open.map(\.chat))
        let newMessages = Set(open.compactMap(\.message))
        markerLock.lock()
        let changedChats = chatMarkers.symmetricDifference(newChats)
        let changedMessages = messageMarkers.symmetricDifference(newMessages)
        chatMarkers = newChats
        messageMarkers = newMessages
        markerLock.unlock()

        // Redraw the chats and messages whose marker changed.
        guard !changedChats.isEmpty || !changedMessages.isEmpty else {
            return
        }
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        databaseStorage.asyncWrite { tx in
            for chat in changedChats.union(changedMessages.map(\.chat)) {
                if let thread = chat.thread(tx: tx) {
                    databaseStorage.touch(thread: thread, shouldReindex: false, shouldUpdateChatListUi: true, tx: tx)
                }
            }
            for message in changedMessages {
                if let interaction = message.message(tx: tx) {
                    databaseStorage.touch(interaction: interaction, shouldReindex: false, tx: tx)
                }
            }
        }
    }

    /// Whether a chat has an open reminder. Safe to call from any thread.
    public func hasReminder(thread: TSThread) -> Bool {
        markerLock.lock()
        let isEmpty = chatMarkers.isEmpty
        markerLock.unlock()
        guard !isEmpty, let reference = IvyChatReference(thread: thread) else {
            return false
        }
        markerLock.lock()
        defer { markerLock.unlock() }
        return chatMarkers.contains(reference)
    }

    /// Whether a message has an open reminder. Safe to call from any thread.
    public func hasReminder(message: TSMessage, thread: TSThread) -> Bool {
        markerLock.lock()
        let isEmpty = messageMarkers.isEmpty
        markerLock.unlock()
        guard !isEmpty, let reference = IvyMessageReference(message: message, thread: thread) else {
            return false
        }
        markerLock.lock()
        defer { markerLock.unlock() }
        return messageMarkers.contains(reference)
    }

    // MARK: - Reading

    public func openReminders() -> [IvyReminder] {
        return IvyReminderStore.open(store: store)
    }

    /// Unique ids of chats with a reminder that is due, most overdue first.
    /// The chat list shows these chats at the top.
    public func dueThreadIds(tx: DBReadTransaction) -> [String] {
        let now = Date()
        var result = [String]()
        for reminder in openReminders() where reminder.isDue(at: now) {
            if let threadId = reminder.chat.thread(tx: tx)?.uniqueId, !result.contains(threadId) {
                result.append(threadId)
            }
        }
        return result
    }

    /// Chats with any open reminder, for the marker in the chat list.
    public func chatsWithReminders() -> Set<IvyChatReference> {
        return Set(openReminders().map(\.chat))
    }

    /// Messages with an open reminder, for the marker on the message.
    public func messagesWithReminders() -> Set<IvyMessageReference> {
        return Set(openReminders().compactMap(\.message))
    }
}
