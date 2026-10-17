//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Gives every menu icon the same size.
///
/// Menus mix Signal's icons, which are drawn on a 24 point canvas, with
/// system symbols and smaller assets. iOS fits menu icons into a fixed slot,
/// but the Mac shows them at their own size, so the same menu had icons of
/// different sizes. Every icon is drawn on the same 24 point canvas instead.
enum IvyMenuIcons {

    static let canvasSize = CGSize(square: 24)

    /// System symbols have no padding of their own; this matches the glyphs
    /// of Signal's icons.
    static let symbolBoxSize = CGSize(square: 20)
    static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)

    private static let lock = NSLock()
    private static let cache = NSMapTable<UIImage, UIImage>.weakToStrongObjects()
    private static let normalizedImages = NSHashTable<UIImage>.weakObjects()

    static func normalized(_ image: UIImage?) -> UIImage? {
        guard let image else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if normalizedImages.contains(image) {
            return image
        }
        if let cached = cache.object(forKey: image) {
            return cached
        }
        let result = render(image)
        cache.setObject(result, forKey: image)
        normalizedImages.add(result)
        return result
    }

    private static func render(_ image: UIImage) -> UIImage {
        let source: UIImage
        let box: CGSize
        if image.isSymbolImage {
            source = image.applyingSymbolConfiguration(symbolConfiguration) ?? image
            box = symbolBoxSize
        } else {
            source = image
            box = canvasSize
        }
        guard source.size.width > 0, source.size.height > 0 else {
            return image
        }
        let scale = min(box.width / source.size.width, box.height / source.size.height)
        let drawSize = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = CGPoint(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2,
        )
        let rendered = UIGraphicsImageRenderer(size: canvasSize).image { _ in
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
        let renderingMode: UIImage.RenderingMode = image.renderingMode == .alwaysOriginal ? .alwaysOriginal : .alwaysTemplate
        return rendered.withRenderingMode(renderingMode)
    }

    // MARK: - Mac menus

    private static var isInstalled = false

    /// On the Mac, makes the system menus (context menus, button menus and
    /// the menu bar) show normalized icons.
    static func install() {
#if targetEnvironment(macCatalyst)
        AssertIsOnMainThread()
        guard !isInstalled else {
            return
        }
        isInstalled = true
        for menuClass in [UIMenuElement.self, UIAction.self, UIMenu.self, UICommand.self] as [AnyClass] {
            wrapImageGetter(of: menuClass)
        }
#endif
    }

    /// Wraps the `image` getter if `menuClass` implements it itself.
    /// Inherited getters are wrapped where they are implemented.
    private static func wrapImageGetter(of menuClass: AnyClass) {
        let selector = NSSelectorFromString("image")
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(menuClass, &count) else {
            return
        }
        defer { free(methods) }
        for index in 0..<Int(count) where method_getName(methods[index]) == selector {
            let method = methods[index]
            typealias Getter = @convention(c) (AnyObject, Selector) -> UIImage?
            let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            let wrapped: @convention(block) (AnyObject) -> UIImage? = { element in
                normalized(original(element, selector))
            }
            method_setImplementation(method, imp_implementationWithBlock(wrapped))
        }
    }
}
