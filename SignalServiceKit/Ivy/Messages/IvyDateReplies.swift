//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An answer to a message that names a date, given with the buttons under it.
public enum IvyDateReply: String, Codable, Sendable {
    case accept
    case decline
}

/// "Zusagen / Absagen / Kalender" under incoming messages that name an
/// upcoming date. Which messages get the buttons, and the answers given,
/// which stay on this device.
public enum IvyDateReplies {

    private static let enabledKey = "IvyDateReplyButtons"
    private static let answersKey = "IvyDateReplyAnswers"

    /// How old a message may be. Words like "morgen" or "Samstag" are read
    /// from today, so older messages would get the wrong day.
    public static let maximumMessageAge: TimeInterval = 2 * 24 * 60 * 60

    /// How far ahead a date may be.
    public static let maximumLeadTime: TimeInterval = 180 * 24 * 60 * 60

    /// The most answers kept; the oldest go first.
    static let maximumAnswers = 500

    /// Whether the buttons are shown. On by default; they also need date
    /// detection to be on.
    public static var showsButtons: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The date the buttons are for: the first upcoming date in a recent
    /// message, or nil.
    public static func date(
        in text: String,
        messageDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
    ) -> IvyDetectedDate? {
        guard now.timeIntervalSince(messageDate) <= maximumMessageAge else { return nil }
        let today = calendar.startOfDay(for: now)
        return IvyDateDetection.dates(in: text).first { detected in
            let isUpcoming = detected.isAllDay ? detected.date >= today : detected.date >= now
            return isUpcoming && detected.date.timeIntervalSince(now) <= maximumLeadTime
        }
    }

    // MARK: Answers

    public static func answer(forMessage uniqueId: String, defaults: UserDefaults = .standard) -> IvyDateReply? {
        guard let entry = answers(defaults)[uniqueId] else { return nil }
        return IvyDateReply(rawValue: entry.reply)
    }

    public static func record(
        _ reply: IvyDateReply,
        forMessage uniqueId: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
    ) {
        var all = answers(defaults)
        all[uniqueId] = Entry(reply: reply.rawValue, at: now.timeIntervalSince1970)
        if all.count > maximumAnswers {
            let oldest = all.sorted { $0.value.at < $1.value.at }.prefix(all.count - maximumAnswers)
            for (key, _) in oldest {
                all.removeValue(forKey: key)
            }
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: answersKey)
        }
    }

    private struct Entry: Codable {
        var reply: String
        var at: TimeInterval
    }

    private static func answers(_ defaults: UserDefaults) -> [String: Entry] {
        guard
            let data = defaults.data(forKey: answersKey),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            return [:]
        }
        return decoded
    }
}
