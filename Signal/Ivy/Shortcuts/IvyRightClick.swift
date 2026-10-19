//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if targetEnvironment(macCatalyst)

/// Opens a message's menu on the Mac with any secondary click: the right
/// mouse button, a two-finger click or tap on the trackpad, or Control-click.
/// The system notices these clicks reliably; Ivy then shows the usual
/// message menu at that spot.
@MainActor
final class IvyRightClickMenu: NSObject, UIContextMenuInteractionDelegate {

    private weak var conversation: ConversationViewController?

    private init(conversation: ConversationViewController) {
        self.conversation = conversation
    }

    private static var key: UInt8 = 0

    static func install(on conversation: ConversationViewController, in view: UIView) {
        let menu = IvyRightClickMenu(conversation: conversation)
        view.addInteraction(UIContextMenuInteraction(delegate: menu))
        // The interaction holds its delegate weakly.
        objc_setAssociatedObject(view, &key, menu, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let view = interaction.view else {
            return nil
        }
        let click = IvyClickLocation(point: location, in: view)
        Task { @MainActor [weak self] in
            self?.conversation?.handleSecondaryClickGesture(click)
        }
        // No system menu: the message menu opens instead.
        return nil
    }
}

/// A finished click at a point, for code that reads a gesture's location.
private final class IvyClickLocation: UITapGestureRecognizer {

    private let point: CGPoint
    private weak var sourceView: UIView?

    init(point: CGPoint, in view: UIView) {
        self.point = point
        self.sourceView = view
        super.init(target: nil, action: nil)
    }

    override func location(in view: UIView?) -> CGPoint {
        guard let sourceView else {
            return point
        }
        return sourceView.convert(point, to: view)
    }
}

#endif
