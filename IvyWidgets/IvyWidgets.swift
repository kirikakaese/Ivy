//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct IvyWidgets: WidgetBundle {
    var body: some Widget {
        IvyTodayWidget()
        IvyTasksWidget()
        IvyUnreadWidget()
        if #available(iOS 18, *) {
            IvyNewTaskControl()
        }
    }
}

/// Ivy's own strings, from the same table as the app.
func IvyLocalizedString(_ key: String, comment: String) -> String {
    NSLocalizedString(key, tableName: "Ivy", bundle: .main, comment: comment)
}

enum IvyWidgetStyle {
    static let accent = Color(red: 0.30, green: 0.66, blue: 0.45)
}

// MARK: - Timeline

struct IvyGlanceEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written the glance once.
    let glance: IvyGlance?
}

struct IvyGlanceProvider: TimelineProvider {

    private static var fileURL: URL? {
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "IvyAppGroup") as? String else {
            return nil
        }
        return IvyGlance.fileURL(appGroup: appGroup)
    }

    static func currentGlance() -> IvyGlance? {
        fileURL.flatMap(IvyGlance.read(from:))
    }

    func placeholder(in context: Context) -> IvyGlanceEntry {
        IvyGlanceEntry(date: Date(), glance: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (IvyGlanceEntry) -> Void) {
        completion(IvyGlanceEntry(date: Date(), glance: Self.currentGlance() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IvyGlanceEntry>) -> Void) {
        let now = Date()
        let glance = Self.currentGlance()
        completion(Timeline(entries: Self.entries(for: glance, now: now), policy: .after(Self.nextMidnight(after: now))))
    }

    /// An entry now and one whenever one of today's items ends, so finished
    /// items leave the widget; the app sends a new glance when data changes.
    static func entries(for glance: IvyGlance?, now: Date, calendar: Calendar = .current) -> [IvyGlanceEntry] {
        var dates = [now]
        for item in glance?.todayRemaining(at: now, calendar: calendar) ?? [] where !item.isAllDay {
            if let end = item.end, end > now {
                dates.append(end.addingTimeInterval(1))
            }
        }
        dates.append(nextMidnight(after: now, calendar: calendar))
        return Set(dates).sorted().map { IvyGlanceEntry(date: $0, glance: glance) }
    }

    static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? date.addingTimeInterval(86_400)
    }
}

// MARK: - Widgets

struct IvyTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IvyToday", provider: IvyGlanceProvider()) { entry in
            IvyTodayView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(IvyLink.calendar.url)
        }
        .configurationDisplayName(IvyLocalizedString("WIDGET_TODAY_TITLE", comment: "Name of the widget with today's events, due tasks and reminders."))
        .description(IvyLocalizedString("WIDGET_TODAY_DESCRIPTION", comment: "Description of the Today widget in the widget gallery."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct IvyTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IvyTasks", provider: IvyGlanceProvider()) { entry in
            IvyTasksView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(IvyLink.tasks.url)
        }
        .configurationDisplayName(IvyLocalizedString("TASKS_TITLE", comment: "Title of the list of tasks."))
        .description(IvyLocalizedString("WIDGET_TASKS_DESCRIPTION", comment: "Description of the Tasks widget in the widget gallery."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

struct IvyUnreadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "IvyUnread", provider: IvyGlanceProvider()) { entry in
            IvyUnreadView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(IvyLink.chats.url)
        }
        .configurationDisplayName(IvyLocalizedString("WIDGET_UNREAD_TITLE", comment: "Name of the widget that shows the number of unread messages."))
        .description(IvyLocalizedString("WIDGET_UNREAD_DESCRIPTION", comment: "Description of the Unread widget in the widget gallery."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

/// A Control Center button that opens a new task in Ivy.
@available(iOS 18, *)
struct IvyNewTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "IvyNewTask") {
            ControlWidgetButton(action: OpenURLIntent(IvyLink.newTask.url)) {
                Label(IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task."), systemImage: "checklist")
            }
        }
        .displayName(LocalizedStringResource(stringLiteral: IvyLocalizedString("TASK_NEW", comment: "Button that makes a new task.")))
    }
}
