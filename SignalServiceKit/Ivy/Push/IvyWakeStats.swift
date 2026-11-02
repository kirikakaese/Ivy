//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation

/// How push relay wake-ups turned out over the last week, counted on this
/// device only: with a new message, with nothing new while a message was
/// still shown (repeated quietly), or with nothing new (the fallback).
/// The relay can't tell these apart, and nothing is sent anywhere.
public enum IvyWakeStats {

    public enum Outcome: String, CaseIterable, Sendable {
        case message
        case alreadyShown
        case empty
    }

    static let daysKept = 7
    private static let key = "IvyWakeStats"

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func record(
        _ outcome: Outcome,
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = CurrentAppContext().appUserDefaults(),
    ) {
        var days = defaults.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
        days[dayKey(now, calendar: calendar), default: [:]][outcome.rawValue, default: 0] += 1
        if let oldest = calendar.date(byAdding: .day, value: -(daysKept - 1), to: now) {
            let cutoff = dayKey(oldest, calendar: calendar)
            days = days.filter { $0.key >= cutoff }
        }
        defaults.set(days, forKey: key)
        Logger.info("Push relay wake-up: \(outcome.rawValue)")
    }

    /// The counts of the last seven days, today included.
    public static func lastWeek(
        now: Date = Date(),
        calendar: Calendar = .current,
        defaults: UserDefaults = CurrentAppContext().appUserDefaults(),
    ) -> [Outcome: Int] {
        let days = defaults.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
        guard let oldest = calendar.date(byAdding: .day, value: -(daysKept - 1), to: now) else {
            return [:]
        }
        let cutoff = dayKey(oldest, calendar: calendar)
        var totals = [Outcome: Int]()
        for (day, counts) in days where day >= cutoff {
            for (name, count) in counts {
                if let outcome = Outcome(rawValue: name) {
                    totals[outcome, default: 0] += count
                }
            }
        }
        return totals
    }
}
