//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import ObjectiveC
import SignalServiceKit
import UIKit

/// Ivy's text size: View > Make Text Bigger (⌘+), Make Text Smaller (⌘−)
/// and Actual Size (⌘0), like Messages on the Mac. Kept per device.
///
/// The app's fonts follow the system text size (Dynamic Type). Ivy sets a
/// text size of its own on its windows, and also answers with it where the
/// app asks for the system's text size, which is where chats are drawn.
enum IvyZoom {

    /// From smallest to largest; `.large` is the system default.
    static let sizes: [UIContentSizeCategory] = [
        .small,
        .medium,
        .large,
        .extraLarge,
        .extraExtraLarge,
        .extraExtraExtraLarge,
        .accessibilityMedium,
        .accessibilityLarge,
    ]
    static let defaultIndex = 2

    private static let key = "IvyZoomLevel"
    private static let lock = NSLock()
    /// Read while chats are drawn off the main thread.
    private static var currentOverride: UIContentSizeCategory?

    static var index: Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultIndex
        }
        return min(max(UserDefaults.standard.integer(forKey: key), 0), sizes.count - 1)
    }

    static var canZoomIn: Bool { index < sizes.count - 1 }
    static var canZoomOut: Bool { index > 0 }
    static var isActualSize: Bool { index == defaultIndex }

    /// The text size Ivy uses instead of the system's, if any.
    static var overrideSize: UIContentSizeCategory? {
        lock.lock()
        defer { lock.unlock() }
        return currentOverride
    }

    // MARK: - Changing

    @MainActor
    static func zoomIn() {
        setIndex(index + 1)
    }

    @MainActor
    static func zoomOut() {
        setIndex(index - 1)
    }

    @MainActor
    static func reset() {
        setIndex(defaultIndex)
    }

    @MainActor
    private static func setIndex(_ newIndex: Int) {
        let clamped = min(max(newIndex, 0), sizes.count - 1)
        guard clamped != index else {
            return
        }
        UserDefaults.standard.set(clamped, forKey: key)
        start()
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            apply(to: window)
        }
        // Screens that measure text again when the system text size
        // changes do so now.
        NotificationCenter.default.post(
            name: UIContentSizeCategory.didChangeNotification,
            object: UIApplication.shared,
            userInfo: [UIContentSizeCategory.newValueUserInfoKey: sizes[clamped]],
        )
    }

    // MARK: - Applying

    /// Called at launch: remembers the size and answers the app's
    /// questions for the text size with it.
    @MainActor
    static func start() {
        let size: UIContentSizeCategory? = isActualSize ? nil : sizes[index]
        lock.lock()
        currentOverride = size
        lock.unlock()
        installTextSizeAnswer()
    }

    @MainActor
    static func apply(to window: UIWindow?) {
        guard let window else {
            return
        }
        if #available(iOS 17, *) {
            if let size = overrideSize {
                window.traitOverrides.preferredContentSizeCategory = size
            } else if window.traitOverrides.contains(UITraitPreferredContentSizeCategory.self) {
                window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            }
        }
    }

    private static var isAnswerInstalled = false

    /// Chats are laid out off the main thread, where only the app's text
    /// size counts, not the window's. So the app's text size answers with
    /// Ivy's while one is set.
    @MainActor
    private static func installTextSizeAnswer() {
        guard !isAnswerInstalled else {
            return
        }
        isAnswerInstalled = true
        guard
            let original = class_getInstanceMethod(UIApplication.self, #selector(getter: UIApplication.preferredContentSizeCategory)),
            let replacement = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.ivy_preferredContentSizeCategory))
        else {
            Logger.warn("Couldn't install the text size")
            return
        }
        method_exchangeImplementations(original, replacement)
    }
}

extension UIApplication {
    /// After `IvyZoom.installTextSizeAnswer()`, this runs for
    /// `preferredContentSizeCategory`, and calling it runs the system's.
    @objc
    fileprivate func ivy_preferredContentSizeCategory() -> UIContentSizeCategory {
        IvyZoom.overrideSize ?? ivy_preferredContentSizeCategory()
    }
}

// MARK: - Commands

extension ConversationSplitViewController {

    @objc
    func ivyZoomIn() {
        IvyZoom.zoomIn()
    }

    @objc
    func ivyZoomOut() {
        IvyZoom.zoomOut()
    }

    @objc
    func ivyZoomReset() {
        IvyZoom.reset()
    }
}
