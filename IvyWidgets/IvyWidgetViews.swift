//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import WidgetKit

// MARK: - Today

struct IvyTodayView: View {
    let entry: IvyGlanceEntry
    @Environment(\.widgetFamily) private var family

    private var items: [IvyGlance.Item] {
        entry.glance?.todayRemaining(at: entry.date) ?? []
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let first = items.first {
                Text(verbatim: "\(IvyItemTime(item: first).text) \(first.title)")
            } else {
                Text(IvyStrings.nothingToday)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if items.isEmpty {
                    Text(IvyStrings.nothingToday).font(.headline).widgetAccentable()
                }
                ForEach(items.prefix(2)) { item in
                    Text(item.title).font(.headline).lineLimit(1).widgetAccentable()
                    Text(IvyItemTime(item: item).text).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                IvyWidgetHeader(title: entry.date.formatted(.dateTime.weekday(.wide).day()), systemImage: "calendar")
                if entry.glance == nil {
                    IvyNoDataView()
                } else if items.isEmpty {
                    Text(IvyStrings.nothingToday).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(items.prefix(rowCount)) { item in
                        Link(destination: item.link) {
                            IvyItemRow(item: item, showsTime: true)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var rowCount: Int {
        switch family {
        case .systemSmall: return 3
        case .systemLarge: return 8
        default: return 4
        }
    }
}

// MARK: - Tasks

struct IvyTasksView: View {
    let entry: IvyGlanceEntry
    @Environment(\.widgetFamily) private var family

    private var tasks: [IvyGlance.Item] { entry.glance?.tasks ?? [] }
    private var openCount: Int { entry.glance?.openTaskCount ?? 0 }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "checklist").font(.caption)
                    Text(verbatim: "\(openCount)").font(.title3.bold()).widgetAccentable()
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(IvyStrings.tasks) · \(openCount)").font(.headline).widgetAccentable()
                ForEach(tasks.prefix(2)) { task in
                    Text(task.title).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    IvyWidgetHeader(title: IvyStrings.tasks, systemImage: "checklist")
                    Spacer()
                    if openCount > 0 {
                        Text(verbatim: "\(openCount)").font(.headline).foregroundStyle(IvyWidgetStyle.accent)
                    }
                }
                if entry.glance == nil {
                    IvyNoDataView()
                } else if tasks.isEmpty {
                    Text(IvyStrings.noOpenTasks).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(tasks.prefix(rowCount)) { task in
                        Link(destination: task.link) {
                            IvyItemRow(item: task, showsTime: task.start != nil)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var rowCount: Int {
        switch family {
        case .systemSmall: return 3
        case .systemLarge: return 8
        default: return 4
        }
    }
}

// MARK: - Unread

struct IvyUnreadView: View {
    let entry: IvyGlanceEntry
    @Environment(\.widgetFamily) private var family

    private var count: Int { entry.glance?.unreadCount ?? 0 }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(count)", systemImage: "bubble.left.and.bubble.right")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.caption)
                    Text(verbatim: "\(count)").font(.title3.bold()).widgetAccentable()
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                IvyWidgetHeader(title: "Ivy", systemImage: "leaf.fill")
                Spacer(minLength: 0)
                Text(verbatim: "\(count)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? IvyWidgetStyle.accent : .secondary)
                    .minimumScaleFactor(0.5)
                Text(IvyStrings.unread).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Parts

private struct IvyWidgetHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(IvyWidgetStyle.accent)
            .lineLimit(1)
    }
}

private struct IvyNoDataView: View {
    var body: some View {
        Text(IvyStrings.noData).font(.caption).foregroundStyle(.secondary)
    }
}

private struct IvyItemRow: View {
    let item: IvyGlance.Item
    let showsTime: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(IvyWidgetStyle.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title.isEmpty ? " " : item.title).font(.subheadline).lineLimit(1)
                if showsTime {
                    Text(IvyItemTime(item: item).text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var icon: String {
        switch item.kind {
        case .event: return "calendar"
        case .task: return "circle"
        case .reminder: return "bell"
        }
    }
}

/// "All day", "14:30", or a date for a task due another day.
struct IvyItemTime {
    let item: IvyGlance.Item

    var text: String {
        guard let start = item.start else {
            return ""
        }
        if !Calendar.current.isDateInToday(start) {
            return item.isAllDay
                ? start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                : start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        }
        if item.isAllDay {
            return IvyStrings.allDay
        }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

enum IvyStrings {
    static var tasks: String { IvyLocalizedString("TASKS_TITLE", comment: "Title of the list of tasks.") }
    static var nothingToday: String { IvyLocalizedString("HOME_NOTHING_TODAY", comment: "Shown on Home when there are no events or reminders today.") }
    static var noOpenTasks: String { IvyLocalizedString("TASKS_EMPTY_TITLE", comment: "Title shown in the list of tasks when there are no open tasks.") }
    static var allDay: String { IvyLocalizedString("TASK_ALL_DAY", comment: "Switch that makes a task due on a day without a time.") }
    static var unread: String { IvyLocalizedString("WIDGET_UNREAD_LABEL", comment: "Label under the number of unread messages in a widget.") }
    static var noData: String { IvyLocalizedString("WIDGET_NO_DATA", comment: "Shown in a widget before Ivy has been opened.") }
}
