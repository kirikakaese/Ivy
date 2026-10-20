//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What Ivy underlines in messages. Messages are only read on this device.
public enum IvyMessageDetection {

    private static let datesKey = "IvyDetectDates"
    private static let tasksKey = "IvyDetectTasks"

    /// Whether dates and times in messages are underlined. On by default.
    public static var detectsDates: Bool {
        get { UserDefaults.standard.object(forKey: datesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: datesKey) }
    }

    /// Whether requests like "Can you…" are underlined. On by default.
    public static var detectsTasks: Bool {
        get { UserDefaults.standard.object(forKey: tasksKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: tasksKey) }
    }
}

/// A part of a message that reads like something to do, such as "Can you
/// pick up milk" or "Vergiss nicht, Oma anzurufen".
public struct IvyTaskPhrase: Equatable, Sendable {
    /// Where the phrase is, in UTF-16 units of the text.
    public let range: NSRange
    public let text: String
    /// The phrase as a task title: "Pick up milk".
    public let title: String
}

public enum IvyTaskPhrases {

    /// Words that start a request or reminder, and whether the task title
    /// leaves them out.
    private static let triggers: [(words: String, isDropped: Bool)] = [
        ("can you please", true),
        ("could you please", true),
        ("can you", true),
        ("could you", true),
        ("would you", true),
        ("will you", true),
        ("please", true),
        ("don't forget to", true),
        ("don’t forget to", true),
        ("dont forget to", true),
        ("do not forget to", true),
        ("don't forget", true),
        ("don’t forget", true),
        ("dont forget", true),
        ("do not forget", true),
        ("remember to", true),
        ("make sure", false),
        ("todo:", true),
        ("to do:", true),
        ("to-do:", true),
        ("kannst du bitte", true),
        ("könntest du bitte", true),
        ("kannst du", true),
        ("könntest du", true),
        ("würdest du", true),
        ("bitte", true),
        ("vergiss nicht", true),
        ("nicht vergessen", true),
        ("denk dran", true),
        ("denk daran", true),
        ("denkst du an", true),
    ]

    private static let triggerExpression: NSRegularExpression? = {
        let alternatives = triggers
            .map { $0.words }
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{N}])(" + alternatives + ")(?![\\p{L}\\p{N}])",
            options: [.caseInsensitive],
        )
    }()

    static let maxLength = 120

    /// Phrases in `text` that read like something to do. A phrase stops
    /// before any of `otherRanges` (links, dates and the like), so the two
    /// never overlap.
    public static func phrases(in text: String, avoiding otherRanges: [NSRange] = []) -> [IvyTaskPhrase] {
        guard let triggerExpression, !text.isEmpty else {
            return []
        }
        let string = text as NSString
        var result = [IvyTaskPhrase]()
        for clause in clauses(in: string) {
            guard let match = triggerExpression.firstMatch(in: text, range: clause) else {
                continue
            }
            var end = NSMaxRange(clause)
            for other in otherRanges where NSIntersectionRange(other, NSRange(location: match.range.location, length: end - match.range.location)).length > 0 {
                if other.location <= match.range.location {
                    end = match.range.location
                } else {
                    end = min(end, other.location)
                }
            }
            guard end > NSMaxRange(match.range) else {
                continue
            }
            let range = trimmed(NSRange(location: match.range.location, length: end - match.range.location), in: string)
            let phraseText = string.substring(with: range)
            guard
                range.length <= maxLength,
                let title = title(fromPhrase: phraseText)
            else {
                continue
            }
            result.append(IvyTaskPhrase(range: range, text: phraseText, title: title))
        }
        return result
    }

    /// A task title for a phrase: without "Can you" and the like, starting
    /// with a capital letter. Nil when too little is left to do.
    public static func title(fromPhrase phrase: String) -> String? {
        var rest = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = rest.lowercased()
        let trigger = triggers
            .sorted { $0.words.count > $1.words.count }
            .first { lowercased.hasPrefix($0.words) }
        let minimumWords: Int
        if let trigger {
            minimumWords = trigger.words.hasSuffix(":") ? 1 : 2
            if trigger.isDropped {
                rest = String(rest.dropFirst(trigger.words.count))
            }
        } else {
            minimumWords = 2
        }
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,:;–-").union(.whitespaces))
        for filler in ["please ", "bitte ", "to "] where rest.lowercased().hasPrefix(filler) {
            rest = String(rest.dropFirst(filler.count))
        }
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,:;–-?!.").union(.whitespaces))
        for filler in [", please", " please", ", bitte", " bitte"] where rest.lowercased().hasSuffix(filler) {
            rest = String(rest.dropLast(filler.count))
        }
        let words = rest.split(whereSeparator: \.isWhitespace)
        guard words.count >= minimumWords, rest.contains(where: \.isLetter) else {
            return nil
        }
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// Sentences and lines of `text`. A period only ends a sentence when a
    /// space or the end follows, so "10.30" stays whole.
    private static func clauses(in string: NSString) -> [NSRange] {
        var clauses = [NSRange]()
        var start = 0
        let length = string.length
        var index = 0
        while index < length {
            let character = string.character(at: index)
            let isNewline = character == 0x0A || character == 0x0D
            var isEnd = isNewline
            if !isEnd, character == 0x2E || character == 0x21 || character == 0x3F {
                let next = index + 1 < length ? string.character(at: index + 1) : 0x20
                isEnd = next == 0x20 || next == 0x0A || next == 0x0D
            }
            if isEnd {
                if index > start {
                    clauses.append(NSRange(location: start, length: index - start))
                }
                start = index + 1
            }
            index += 1
        }
        if length > start {
            clauses.append(NSRange(location: start, length: length - start))
        }
        return clauses
    }

    private static func trimmed(_ range: NSRange, in string: NSString) -> NSRange {
        let trailing = CharacterSet(charactersIn: " ,:;–-?!.\t")
        var length = range.length
        while length > 0 {
            let scalar = UnicodeScalar(string.character(at: range.location + length - 1))
            guard let scalar, trailing.contains(scalar) else {
                break
            }
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }
}
