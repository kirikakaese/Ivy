//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

@testable import Signal

final class IvyMenuIconsTest: XCTestCase {

    private func image(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testSymbolsAndAssetsGetTheSameCanvas() throws {
        let symbol = try XCTUnwrap(IvyMenuIcons.normalized(UIImage(systemName: "folder")))
        let small = try XCTUnwrap(IvyMenuIcons.normalized(image(size: CGSize(square: 20))))
        let wide = try XCTUnwrap(IvyMenuIcons.normalized(image(size: CGSize(width: 48, height: 24))))

        XCTAssertEqual(symbol.size, IvyMenuIcons.canvasSize)
        XCTAssertEqual(small.size, IvyMenuIcons.canvasSize)
        XCTAssertEqual(wide.size, IvyMenuIcons.canvasSize)
    }

    func testKeepsColoredIconsColored() throws {
        let original = image(size: CGSize(square: 16)).withRenderingMode(.alwaysOriginal)
        let template = image(size: CGSize(square: 16)).withRenderingMode(.alwaysTemplate)

        XCTAssertEqual(try XCTUnwrap(IvyMenuIcons.normalized(original)).renderingMode, .alwaysOriginal)
        XCTAssertEqual(try XCTUnwrap(IvyMenuIcons.normalized(template)).renderingMode, .alwaysTemplate)
        XCTAssertEqual(try XCTUnwrap(IvyMenuIcons.normalized(UIImage(systemName: "bell"))).renderingMode, .alwaysTemplate)
    }

    func testNormalizingTwiceChangesNothing() throws {
        let once = try XCTUnwrap(IvyMenuIcons.normalized(UIImage(systemName: "pin")))
        XCTAssertTrue(IvyMenuIcons.normalized(once) === once)
        XCTAssertNil(IvyMenuIcons.normalized(nil))
    }

    #if targetEnvironment(macCatalyst)
    @MainActor
    func testMacMenusShowNormalizedIcons() {
        IvyMenuIcons.install()
        let action = UIAction(title: "Action", image: UIImage(systemName: "folder")) { _ in }
        let menu = UIMenu(title: "Menu", image: UIImage(systemName: "bell"), children: [action])

        XCTAssertEqual(action.image?.size, IvyMenuIcons.canvasSize)
        XCTAssertEqual(menu.image?.size, IvyMenuIcons.canvasSize)
    }
    #endif
}
