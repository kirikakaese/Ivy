//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A string from Ivy's own table, `Ivy.strings`.
///
/// Upstream strings use `OWSLocalizedString` and Signal's translations. Ivy's
/// strings live in a separate table that upstream merges never touch. A string
/// that is not translated into the current language falls back to English.
public func IvyLocalizedString(_ key: String, comment: String) -> String {
    return IvyStrings.localizedString(key, bundle: .main.app)
}

public enum IvyStrings {

    public static let tableName = "Ivy"

    private static let missing = "\u{FFFF}"

    public static func localizedString(_ key: String, bundle: Bundle) -> String {
        let value = bundle.localizedString(forKey: key, value: missing, table: tableName)
        if value != missing {
            return value
        }
        if
            let englishPath = bundle.path(forResource: "en", ofType: "lproj"),
            let english = Bundle(path: englishPath)
        {
            let englishValue = english.localizedString(forKey: key, value: missing, table: tableName)
            if englishValue != missing {
                return englishValue
            }
        }
        Logger.warn("Missing Ivy string \(key)")
        return key
    }
}
