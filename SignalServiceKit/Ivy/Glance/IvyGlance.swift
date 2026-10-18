//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

// This file is also part of the widget extension and the Mac menu bar
// plugin, which don't link SignalServiceKit. It may only use Foundation.

public import Foundation

/// A small summary for widgets and the Mac menu bar: today's agenda, open
/// tasks and the unread count. The app writes it to its app group whenever
/// it changes; widgets and the menu bar only read it.
public struct IvyGlance: Codable, Equatable, Sendable {

    public struct Item: Codable, Equatable, Identifiable, Sendable {

        public enum Kind: String, Codable, Sendable {
            case event
            case task
            case reminder
        }

        public var id: String
        public var kind: Kind
        public var title: String
        /// The start of an event, or when a task or reminder is due.
        public var start: Date?
        /// The end of an event; the same as `start` otherwise.
        public var end: Date?
        public var isAllDay: Bool
        /// Opens the item in Ivy.
        public var link: URL

        public init(id: String, kind: Kind, title: String, start: Date?, end: Date?, isAllDay: Bool, link: URL) {
            self.id = id
            self.kind = kind
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.link = link
        }
    }

    public var writtenAt: Date
    public var unreadCount: Int
    /// Today's events, due tasks and reminders, earliest first.
    public var today: [Item]
    /// Open tasks, soonest due first; tasks without a due date last.
    public var tasks: [Item]
    public var openTaskCount: Int

    public init(writtenAt: Date, unreadCount: Int, today: [Item], tasks: [Item], openTaskCount: Int) {
        self.writtenAt = writtenAt
        self.unreadCount = unreadCount
        self.today = Array(today.prefix(Self.maxItems))
        self.tasks = Array(tasks.prefix(Self.maxItems))
        self.openTaskCount = openTaskCount
    }

    public static let empty = IvyGlance(writtenAt: .distantPast, unreadCount: 0, today: [], tasks: [], openTaskCount: 0)

    /// No widget or menu shows more.
    public static let maxItems = 8

    /// Today's items that haven't ended at `now`. All-day items stay all day.
    public func todayRemaining(at now: Date, calendar: Calendar = .current) -> [Item] {
        guard calendar.isDate(writtenAt, inSameDayAs: now) else {
            // Written on another day: today's items are unknown.
            return []
        }
        return today.filter { item in
            item.isAllDay || (item.end ?? item.start ?? now) >= now
        }
    }

    // MARK: - Storage

    public static let fileName = "IvyGlance.json"

    public static func fileURL(appGroup: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    public static func read(from url: URL) -> IvyGlance? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(IvyGlance.self, from: data)
    }

    public func encoded() -> Data? {
        try? Self.encoder.encode(self)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Links that open a place in Ivy, used by widgets, the menu bar and
/// shortcuts: `sgnl://ivy/<place>`, with `?id=` for one task or event.
public enum IvyLink: Equatable, Sendable {
    case home
    case chats
    case calendar
    case calls
    case tasks
    case newTask
    case newEvent
    case task(id: String)
    case event(id: String)

    static let scheme = "sgnl"
    static let host = "ivy"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch self {
        case .home: components.path = "/home"
        case .chats: components.path = "/chats"
        case .calendar: components.path = "/calendar"
        case .calls: components.path = "/calls"
        case .tasks: components.path = "/tasks"
        case .newTask: components.path = "/tasks/new"
        case .newEvent: components.path = "/calendar/new"
        case .task(let id):
            components.path = "/task"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        case .event(let id):
            components.path = "/event"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        }
        return components.url!
    }

    public init?(url: URL) {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == Self.scheme,
            components.host?.lowercased() == Self.host
        else {
            return nil
        }
        let id = components.queryItems?.first(where: { $0.name == "id" })?.value
        switch components.path {
        case "/home": self = .home
        case "/chats": self = .chats
        case "/calendar": self = .calendar
        case "/calls": self = .calls
        case "/tasks": self = .tasks
        case "/tasks/new": self = .newTask
        case "/calendar/new": self = .newEvent
        case "/task":
            guard let id, !id.isEmpty else { return nil }
            self = .task(id: id)
        case "/event":
            guard let id, !id.isEmpty else { return nil }
            self = .event(id: id)
        default:
            return nil
        }
    }
}
