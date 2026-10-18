//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

enum IvyTaskUI {

    static var tasksTitle: String {
        IvyLocalizedString("TASKS_TITLE", comment: "Title of the list of tasks.")
    }

    static var addTaskTitle: String {
        IvyLocalizedString("TASK_ADD", comment: "Action that makes a task, for example from a message.")
    }

    static func title(for group: IvyTask.Group) -> String {
        switch group {
        case .overdue:
            return IvyLocalizedString("TASKS_GROUP_OVERDUE", comment: "Header of the tasks whose due date has passed.")
        case .today:
            return IvyLocalizedString("TASKS_GROUP_TODAY", comment: "Header of the tasks that are due today.")
        case .upcoming:
            return IvyLocalizedString("TASKS_GROUP_UPCOMING", comment: "Header of the tasks that are due after today.")
        case .someday:
            return IvyLocalizedString("TASKS_GROUP_NO_DATE", comment: "Header of the tasks without a due date.")
        case .done:
            return IvyLocalizedString("TASKS_GROUP_DONE", comment: "Header of the tasks that are done.")
        }
    }

    static func title(for priority: IvyTask.Priority) -> String {
        switch priority {
        case .none:
            return IvyLocalizedString("TASK_PRIORITY_NONE", comment: "Task priority: none.")
        case .low:
            return IvyLocalizedString("TASK_PRIORITY_LOW", comment: "Task priority: low.")
        case .medium:
            return IvyLocalizedString("TASK_PRIORITY_MEDIUM", comment: "Task priority: medium.")
        case .high:
            return IvyLocalizedString("TASK_PRIORITY_HIGH", comment: "Task priority: high.")
        }
    }

    /// "!", "!!" or "!!!" in front of a task's title, like Apple Reminders.
    static func marker(for priority: IvyTask.Priority) -> String? {
        priority == .none ? nil : String(repeating: "!", count: priority.rawValue)
    }

    /// "Today, 14:00", "Tomorrow" or "12 Nov 2026".
    static func dueText(for task: IvyTask) -> String? {
        guard let dueAt = task.dueAt else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = task.isAllDay ? .none : .short
        return formatter.string(from: dueAt)
    }

    /// The line under a task's title: due date, list, subtasks.
    static func subtitle(for task: IvyTask, listName: String?) -> String? {
        var parts = [String]()
        if let dueText = dueText(for: task) {
            parts.append(dueText)
        }
        if let listName {
            parts.append(listName)
        }
        let progress = task.subtaskProgress
        if progress.total > 0 {
            parts.append("\(progress.done)/\(progress.total)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func checkboxImage(isDone: Bool) -> UIImage? {
        UIImage(systemName: isDone ? "checkmark.circle.fill" : "circle")
    }

    /// A task made from a message, before the user edits it.
    static func task(from message: TSMessage, thread: TSThread) -> IvyTask {
        let text = message.body ?? ""
        let source = IvyMessageReference(message: message, thread: thread).map {
            IvyTask.Source(message: $0, quote: IvyTask.quote(fromMessageText: text))
        }
        return IvyTask(title: IvyTask.title(fromMessageText: text), source: source)
    }
}

extension UIViewController {

    /// Opens the editor for a new or existing task.
    func ivyPresentTaskEditor(_ task: IvyTask, isNew: Bool) {
        let editor = IvyTaskEditorViewController(task: task, isNew: isNew)
        presentFormSheet(OWSNavigationController(rootViewController: editor), animated: true)
    }

    func ivyPresentTasks() {
        presentFormSheet(OWSNavigationController(rootViewController: IvyTasksViewController()), animated: true)
    }
}

// MARK: - Conversation

extension ConversationViewController {

    /// "Add Task" in a message's context menu.
    func ivyAddTaskContextMenuAction(interaction: TSInteraction, thread: TSThread) -> ContextMenuAction? {
        guard let message = interaction as? TSMessage else {
            return nil
        }
        return ContextMenuAction(
            title: IvyTaskUI.addTaskTitle,
            image: UIImage(systemName: "checklist"),
        ) { [weak self] _ in
            self?.ivyPresentTaskEditor(IvyTaskUI.task(from: message, thread: thread), isNew: true)
        }
    }
}

// MARK: - Notifications

enum IvyTaskActionHandler {

    /// Handles a task notification. Returns false for other notifications.
    @MainActor
    static func handle(_ response: UNNotificationResponse) -> Bool {
        guard let taskId = IvyTaskNotifications.taskId(of: response.notification.request) else {
            return false
        }
        let manager = IvyTaskManager.shared
        switch response.actionIdentifier {
        case IvyTaskNotifications.Action.done.rawValue:
            manager.setDone(id: taskId, true)
        case IvyTaskNotifications.Action.tomorrow.rawValue:
            manager.moveToTomorrow(id: taskId)
        default:
            guard let task = manager.task(id: taskId), let frontmost = CurrentAppContext().frontmostViewController() else {
                return true
            }
            frontmost.ivyPresentTaskEditor(task, isNew: false)
        }
        return true
    }
}
