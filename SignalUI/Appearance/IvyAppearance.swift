//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Ivy's appearance settings (Settings > Appearance): the accent colour,
/// the kind of dark mode, how dense the chat list is and the shape of
/// message bubbles. Read while drawing, also off the main thread, so the
/// values are cached and only written on the main thread.
public enum IvyAppearance {

    public enum Accent: String, CaseIterable, Sendable {
        case ivy, moss, petrol, blue, violet, pink, coral, orange, gold
        /// Follows the app icon.
        case icon

        /// Light and dark mode values.
        fileprivate var hex: (light: UInt32, dark: UInt32) {
            switch self {
            case .ivy, .icon: return (0x2E7D4F, 0x3A9A62)
            case .moss: return (0x5E7A26, 0x7A9A3A)
            case .petrol: return (0x137A77, 0x1F9E9A)
            case .blue: return (0x2563EB, 0x3B82F6)
            case .violet: return (0x7C3AED, 0x8B5CF6)
            case .pink: return (0xDB2777, 0xEC4899)
            case .coral: return (0xD94A3E, 0xF2665A)
            case .orange: return (0xD9700F, 0xF28C28)
            case .gold: return (0xB08617, 0xD4A72C)
            }
        }

        public var swatch: UIColor {
            UIColor(rgbHex: hex.dark)
        }
    }

    public enum DarkStyle: String, CaseIterable, Sendable {
        /// Today's dark mode.
        case dark
        /// Black surfaces too, for OLED screens.
        case black
        /// Soft grey.
        case dimmed
    }

    public enum Density: String, CaseIterable, Sendable {
        case compact, normal, airy
    }

    public enum BubbleShape: String, CaseIterable, Sendable {
        case round, soft, square
    }

    // MARK: Stored values

    private enum Key {
        static let accent = "IvyAccent"
        /// Written by the app icon picker (IvyAppIcons).
        static let appIcon = "IvyAppIconChoice"
        static let ownBubbles = "IvyAccentOwnBubbles"
        static let darkStyle = "IvyDarkStyle"
        static let density = "IvyChatListDensity"
        static let bubbleShape = "IvyBubbleShape"
        static let bubbleTail = "IvyBubbleTail"
        static let folderAccent = "IvyAccentFollowsFolder"
    }

    private struct Values {
        var accent: Accent
        var iconAccent: Accent
        var colorsOwnBubbles: Bool
        var darkStyle: DarkStyle
        var density: Density
        var bubbleShape: BubbleShape
        var bubbleTail: Bool
        var followsFolderColor: Bool
        var folderAccent: UIColor?

        static func load() -> Values {
            let defaults = UserDefaults.standard
            func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
                defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
            }
            return Values(
                accent: value(Key.accent, Accent.ivy),
                iconAccent: IvyAppearance.accent(forAppIcon: defaults.string(forKey: Key.appIcon)),
                colorsOwnBubbles: defaults.bool(forKey: Key.ownBubbles),
                darkStyle: value(Key.darkStyle, DarkStyle.dark),
                density: value(Key.density, Density.normal),
                bubbleShape: value(Key.bubbleShape, BubbleShape.soft),
                bubbleTail: defaults.object(forKey: Key.bubbleTail) as? Bool ?? true,
                followsFolderColor: defaults.bool(forKey: Key.folderAccent),
                folderAccent: nil,
            )
        }
    }

    /// A colour that asks `make` again each time it is drawn.
    public static func dynamic(_ make: @escaping @Sendable () -> UIColor) -> UIColor {
        UIColor { traits in make().resolvedColor(with: traits) }
    }

    /// Goes up with every change; windows carry it as a trait, so changing
    /// it makes UIKit draw every colour again.
    nonisolated(unsafe) public private(set) static var generation = 0

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cached: Values?

    private static var values: Values {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let loaded = Values.load()
        cached = loaded
        return loaded
    }

    private static func update(_ change: (inout Values) -> Void, store: (UserDefaults) -> Void) {
        lock.lock()
        var new = cached ?? Values.load()
        change(&new)
        cached = new
        generation += 1
        lock.unlock()
        store(UserDefaults.standard)
        DispatchQueue.main.async {
            // Screens redraw as for a change between light and dark mode.
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    // MARK: Settings

    public static var accent: Accent {
        get { values.accent }
        set { update({ $0.accent = newValue }, store: { $0.set(newValue.rawValue, forKey: Key.accent) }) }
    }

    /// The colour that goes with an app icon, for `.icon`.
    public static func accent(forAppIcon name: String?) -> Accent {
        switch name {
        case "AppIcon-ivy-autumn": return .orange
        case "AppIcon-ivy-rainbow", "AppIcon-ivy-progress", "AppIcon-ivy-bi": return .violet
        case "AppIcon-ivy-trans", "AppIcon-ivy-pan": return .pink
        case "AppIcon-ivy-nonbinary": return .gold
        case "AppIcon-ivy-lesbian": return .coral
        case "AppIcon-ivy-glass": return .petrol
        default: return .ivy
        }
    }

    /// Follows the app icon while the accent is `.icon`.
    public static func start() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            let iconAccent = accent(forAppIcon: UserDefaults.standard.string(forKey: Key.appIcon))
            guard iconAccent != values.iconAccent else { return }
            update({ $0.iconAccent = iconAccent }, store: { _ in })
        }
    }

    /// Whether the user's own messages use the accent colour instead of the
    /// chat colour. Off by default.
    public static var colorsOwnBubbles: Bool {
        get { values.colorsOwnBubbles }
        set { update({ $0.colorsOwnBubbles = newValue }, store: { $0.set(newValue, forKey: Key.ownBubbles) }) }
    }

    public static var darkStyle: DarkStyle {
        get { values.darkStyle }
        set { update({ $0.darkStyle = newValue }, store: { $0.set(newValue.rawValue, forKey: Key.darkStyle) }) }
    }

    public static var density: Density {
        get { values.density }
        set { update({ $0.density = newValue }, store: { $0.set(newValue.rawValue, forKey: Key.density) }) }
    }

    public static var bubbleShape: BubbleShape {
        get { values.bubbleShape }
        set { update({ $0.bubbleShape = newValue }, store: { $0.set(newValue.rawValue, forKey: Key.bubbleShape) }) }
    }

    /// Whether bubbles in a row get the small, sharper corner. On by default.
    public static var bubbleTail: Bool {
        get { values.bubbleTail }
        set { update({ $0.bubbleTail = newValue }, store: { $0.set(newValue, forKey: Key.bubbleTail) }) }
    }

    /// Whether a coloured chat folder lends the app its colour while it is
    /// open. Off by default.
    public static var followsFolderColor: Bool {
        get { values.followsFolderColor }
        set { update({ $0.followsFolderColor = newValue; if !newValue { $0.folderAccent = nil } }, store: { $0.set(newValue, forKey: Key.folderAccent) }) }
    }

    /// The colour of the chat folder that is open, while it lends the app
    /// its colour. Not stored.
    public static func setFolderAccent(_ color: UIColor?) {
        let current = values
        let new = current.followsFolderColor ? color : nil
        guard new != current.folderAccent else { return }
        update({ $0.folderAccent = new }, store: { _ in })
    }

    // MARK: Colours

    /// Ivy's accent colour, used wherever Signal used ultramarine.
    public static var accentColor: UIColor {
        let current = values
        if let folderAccent = current.folderAccent {
            return folderAccent
        }
        let accent = current.accent == .icon ? current.iconAccent : current.accent
        if accent == .ivy || accent == .icon {
            return UIColor.byRGBHex(light: 0x2E7D4F, lightHighContrast: 0x1D5C38, dark: 0x3A9A62, darkHighContrast: 0x5CC08A)
        }
        return UIColor.byRGBHex(light: accent.hex.light, dark: accent.hex.dark)
    }

    /// A dark mode surface colour, after the chosen kind of dark mode.
    public static func dark(_ hex: UInt32) -> UInt32 {
        switch values.darkStyle {
        case .dark:
            return hex
        case .black:
            switch hex {
            case 0x1C1C1E: return 0x0E0E0F
            case 0x2C2C2E: return 0x1A1A1C
            case 0x3A3A3C: return 0x2A2A2C
            default: return hex
            }
        case .dimmed:
            switch hex {
            case 0x000000: return 0x1E2126
            case 0x1C1C1E: return 0x2B2F35
            case 0x2C2C2E: return 0x3A3F46
            case 0x3A3A3C: return 0x464C54
            default: return hex
            }
        }
    }

    // MARK: Bubbles

    public static var bubbleWideCornerRadius: CGFloat {
        switch values.bubbleShape {
        case .round: return 22
        case .soft: return 18
        case .square: return 8
        }
    }

    public static var bubbleSharpCornerRadius: CGFloat {
        values.bubbleTail ? (values.bubbleShape == .square ? 3 : 4) : bubbleWideCornerRadius
    }

    // MARK: Chat list

    /// Height of a chat's picture in the chat list.
    public static func chatListAvatarSize(isMac: Bool) -> UInt {
        switch values.density {
        case .compact: return isMac ? 32 : 44
        case .normal: return isMac ? 40 : 56
        case .airy: return isMac ? 48 : 64
        }
    }

    /// Space above and below a chat's picture.
    public static func chatListVerticalMargin(isMac: Bool) -> CGFloat {
        switch values.density {
        case .compact: return isMac ? 5 : 7
        case .normal: return isMac ? 8 : 12
        case .airy: return isMac ? 12 : 14
        }
    }

    /// Lines of the last message under a chat's name.
    public static var chatListSnippetLines: Int {
        values.density == .compact ? 1 : 2
    }
}

/// Carries `IvyAppearance.generation` on the windows. Colours depend on it,
/// so a new value redraws them.
@available(iOS 17, *)
public struct IvyAppearanceTrait: UITraitDefinition {
    public static let defaultValue = 0
    public static let affectsColorAppearance = true
    public static let identifier = "io.github.kirikakaese.ivy.appearance"
    public static let name = "IvyAppearance"
}
