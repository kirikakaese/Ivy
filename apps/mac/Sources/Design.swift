import SwiftUI

/// Tokens from docs/DESIGN.md. Screens use these, not literals.
enum Design {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let sheet: CGFloat = 16
    }

    static let textColumn: CGFloat = 420
    static let accent = Color("Accent")
}

/// A string from Signal's translation table, shared with the Swift app.
func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// A string from Ivy's own table, `Ivy.strings` (same name as in the Swift app; Scripts/ivy/ivy_strings.py looks for it).
func IvyLocalizedString(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Ivy", comment: "")
}
