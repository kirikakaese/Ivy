//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A text the user reuses, typed as `;trigger` in a message. Snippets sync
/// to all Ivy devices (kind "snippet").
public struct IvySnippet: Equatable, Identifiable, Sendable {
    public let id: String
    /// Letters and digits, without the semicolon.
    public var trigger: String
    public var text: String

    public init(id: String = UUID().uuidString, trigger: String, text: String) {
        self.id = id
        self.trigger = trigger
        self.text = text
    }

    /// Typed before the trigger.
    public static let prefix = ";"
    public static let maxTriggerLength = 20
    public static let maxTextLength = 2000

    /// Lowercase letters and digits only, so triggers are easy to type.
    public static func cleanTrigger(_ trigger: String) -> String {
        let allowed = trigger.lowercased().filter { $0.isLetter || $0.isNumber }
        return String(allowed.prefix(maxTriggerLength))
    }
}

public enum IvySnippets {

    static let kind = "snippet"

    private enum Field {
        static let trigger = "trigger"
        static let text = "text"
    }

    /// Sorted by trigger.
    public static func all(store: IvyDataStore?) -> [IvySnippet] {
        guard let store else {
            return []
        }
        return store.entities(kind: kind).compactMap { id, fields in
            guard
                let trigger = IvyDataStore.decode(String.self, from: fields[Field.trigger]),
                let text = IvyDataStore.decode(String.self, from: fields[Field.text])
            else {
                return nil
            }
            return IvySnippet(id: id, trigger: trigger, text: text)
        }.sorted { ($0.trigger, $0.id) < ($1.trigger, $1.id) }
    }

    public static func save(_ snippet: IvySnippet, store: IvyDataStore?) {
        store?.update(kind: kind, entityId: snippet.id, fields: [
            Field.trigger: IvyDataStore.encode(IvySnippet.cleanTrigger(snippet.trigger)),
            Field.text: IvyDataStore.encode(String(snippet.text.prefix(IvySnippet.maxTextLength))),
        ])
    }

    public static func delete(id: String, store: IvyDataStore?) {
        store?.delete(kind: kind, entityId: id)
    }

    // MARK: - Expanding

    public struct Expansion: Equatable, Sendable {
        /// The `;trigger` to replace, in UTF-16 units.
        public let range: NSRange
        public let text: String
    }

    /// When the user just finished typing `;trigger` and a space, newline or
    /// punctuation before `cursor`, the snippet that replaces it.
    public static func expansion(in text: String, cursor: Int, snippets: [IvySnippet]) -> Expansion? {
        guard !snippets.isEmpty else {
            return nil
        }
        let string = text as NSString
        guard cursor > 1, cursor <= string.length else {
            return nil
        }
        // The character just typed ends the trigger.
        let endCharacter = string.substring(with: NSRange(location: cursor - 1, length: 1))
        guard let scalar = endCharacter.unicodeScalars.first, !CharacterSet.alphanumerics.contains(scalar) else {
            return nil
        }
        var start = cursor - 1
        while start > 0 {
            let character = string.substring(with: NSRange(location: start - 1, length: 1))
            guard let scalar = character.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) else {
                break
            }
            start -= 1
        }
        let triggerLength = cursor - 1 - start
        guard triggerLength > 0, start > 0, string.substring(with: NSRange(location: start - 1, length: 1)) == IvySnippet.prefix else {
            return nil
        }
        // The semicolon starts a word.
        if start > 1 {
            let before = string.substring(with: NSRange(location: start - 2, length: 1))
            guard let scalar = before.unicodeScalars.first, CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                return nil
            }
        }
        let trigger = string.substring(with: NSRange(location: start, length: triggerLength)).lowercased()
        guard let snippet = snippets.first(where: { $0.trigger == trigger }) else {
            return nil
        }
        return Expansion(range: NSRange(location: start - 1, length: triggerLength + 1), text: snippet.text)
    }
}
