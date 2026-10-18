//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SignalServiceKit

// Shortcuts and Siri: add a task, ask what's on today, open a section.

@available(iOS 17, *)
struct IvyAddTaskIntent: AppIntent {

    static let title = LocalizedStringResource("INTENT_ADD_TASK_TITLE", defaultValue: "Add Task", table: "Ivy")
    static let description = IntentDescription(LocalizedStringResource(
        "INTENT_ADD_TASK_DESCRIPTION",
        defaultValue: "Adds a task to Ivy, with a reminder when it has a due date.",
        table: "Ivy",
    ))

    @Parameter(title: LocalizedStringResource("INTENT_TASK_PARAMETER", defaultValue: "Task", table: "Ivy"))
    var taskTitle: String

    @Parameter(title: LocalizedStringResource("INTENT_DUE_PARAMETER", defaultValue: "Due", table: "Ivy"))
    var dueAt: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$taskTitle)") {
            \.$dueAt
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IvyShortcuts.waitUntilReady()
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw $taskTitle.needsValueError()
        }
        IvyTaskManager.shared.save(IvyTask(title: title, dueAt: dueAt, reminds: dueAt != nil))
        let format = IvyLocalizedString("INTENT_TASK_ADDED_FORMAT", comment: "Siri's answer after adding a task. Embeds {{ the task's title }}.")
        return .result(dialog: IntentDialog(stringLiteral: String(format: format, title)))
    }
}

@available(iOS 17, *)
struct IvyTodayIntent: AppIntent {

    static let title = LocalizedStringResource("INTENT_TODAY_TITLE", defaultValue: "What's on Today", table: "Ivy")
    static let description = IntentDescription(LocalizedStringResource(
        "INTENT_TODAY_DESCRIPTION",
        defaultValue: "Lists today's remaining events, due tasks and reminders.",
        table: "Ivy",
    ))

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IvyShortcuts.waitUntilReady()
        let glance = IvyGlanceWriter.glance(
            events: IvyEventManager.shared.allEvents(),
            tasks: IvyTaskManager.shared.allTasks(),
            reminders: IvyReminderManager.shared.openReminders(),
            reminderTitle: { _ in IvyLocalizedString("REMINDER_TITLE", comment: "Title of a reminder notification when the chat is unknown.") },
            unreadCount: 0,
            now: Date(),
        )
        return .result(dialog: IntentDialog(stringLiteral: IvyShortcuts.todaySummary(glance.todayRemaining(at: Date()))))
    }
}

@available(iOS 17, *)
enum IvyShortcutSection: String, AppEnum {
    case home
    case chats
    case calendar
    case calls
    case tasks

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("INTENT_SECTION_TYPE", defaultValue: "Section", table: "Ivy"),
    )

    static let caseDisplayRepresentations: [IvyShortcutSection: DisplayRepresentation] = [
        .home: DisplayRepresentation(title: LocalizedStringResource("HOME_TITLE", defaultValue: "Home", table: "Ivy")),
        .chats: DisplayRepresentation(title: LocalizedStringResource("INTENT_SECTION_CHATS", defaultValue: "Chats", table: "Ivy")),
        .calendar: DisplayRepresentation(title: LocalizedStringResource("CALENDAR_TITLE", defaultValue: "Calendar", table: "Ivy")),
        .calls: DisplayRepresentation(title: LocalizedStringResource("INTENT_SECTION_CALLS", defaultValue: "Calls", table: "Ivy")),
        .tasks: DisplayRepresentation(title: LocalizedStringResource("TASKS_TITLE", defaultValue: "Tasks", table: "Ivy")),
    ]

    var link: IvyLink {
        switch self {
        case .home: return .home
        case .chats: return .chats
        case .calendar: return .calendar
        case .calls: return .calls
        case .tasks: return .tasks
        }
    }
}

@available(iOS 17, *)
struct IvyOpenSectionIntent: AppIntent {

    static let title = LocalizedStringResource("INTENT_OPEN_TITLE", defaultValue: "Open in Ivy", table: "Ivy")
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("INTENT_SECTION_TYPE", defaultValue: "Section", table: "Ivy"))
    var section: IvyShortcutSection

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$section)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = AppLifecycleManager.shared.handleOpenUrl(section.link.url)
        return .result()
    }
}

@available(iOS 17, *)
struct IvyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: IvyAddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "New \(.applicationName) task",
            ],
            shortTitle: LocalizedStringResource("INTENT_ADD_TASK_TITLE", defaultValue: "Add Task", table: "Ivy"),
            systemImageName: "checklist",
        )
        AppShortcut(
            intent: IvyTodayIntent(),
            phrases: [
                "What's on today in \(.applicationName)",
                "Show today in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("INTENT_TODAY_TITLE", defaultValue: "What's on Today", table: "Ivy"),
            systemImageName: "calendar",
        )
        AppShortcut(
            intent: IvyOpenSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("INTENT_OPEN_TITLE", defaultValue: "Open in Ivy", table: "Ivy"),
            systemImageName: "leaf",
        )
    }
}

@available(iOS 17, *)
enum IvyShortcuts {

    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notReady

        var localizedStringResource: LocalizedStringResource {
            LocalizedStringResource("INTENT_NOT_READY", defaultValue: "Open Ivy and finish setting it up first.", table: "Ivy")
        }
    }

    /// Waits until the database is open. Shortcuts can run before the app
    /// has finished starting.
    @MainActor
    static func waitUntilReady() async throws {
        try await AppLifecycleManager.shared.appReadiness.waitForAppReady()
        guard IvyData.shared?.store != nil else {
            throw Failure.notReady
        }
    }

    /// "Lunch at 12:00, Pay rent at 17:00." or that nothing is planned.
    static func todaySummary(_ items: [IvyGlance.Item]) -> String {
        guard !items.isEmpty else {
            return IvyLocalizedString("HOME_NOTHING_TODAY", comment: "Shown on Home when there are no events or reminders today.")
        }
        let timeFormat = IvyLocalizedString("INTENT_TODAY_ITEM_FORMAT", comment: "One item in Siri's list of today's items. Embeds {{ the item's title }} and {{ its time }}.")
        let parts = items.map { item -> String in
            guard let start = item.start, !item.isAllDay else {
                return item.title
            }
            return String(format: timeFormat, item.title, DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .short))
        }
        return ListFormatter.localizedString(byJoining: parts)
    }
}
