//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UniformTypeIdentifiers
// Public only where the chat's drop delegate, which is Mac only, needs it.
#if targetEnvironment(macCatalyst)
public import UIKit
#endif

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

// MARK: - Dropping files into a chat

#if targetEnvironment(macCatalyst)

/// Files, pictures and videos dragged from the Finder or another app can be
/// dropped onto a chat's messages on the Mac. They go through the same
/// preview as pasted ones before anything is sent. Text is left to the
/// message field, which takes dropped text itself.
extension ConversationViewController: UIDropInteractionDelegate {

    /// Called from viewWillAppear; does nothing the second time.
    func ivyInstallFileDrop() {
        guard !isInPreviewPlatter, !collectionView.interactions.contains(where: { $0 is UIDropInteraction }) else {
            return
        }
        collectionView.addInteraction(UIDropInteraction(delegate: self))
    }

    /// What a dropped item is sent as, or nil for things that aren't files.
    private static func ivyDropType(of provider: NSItemProvider) -> TypedItemProvider.ItemType? {
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) { return .movie }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { return .image }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) { return .pdf }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return .fileUrl }
        return nil
    }

    public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.items.contains { Self.ivyDropType(of: $0.itemProvider) != nil }
    }

    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .copy)
    }

    public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        let items: [TypedItemProvider] = session.items.compactMap { item in
            Self.ivyDropType(of: item.itemProvider).map { TypedItemProvider(itemProvider: item.itemProvider, itemType: $0) }
        }
        guard !items.isEmpty else { return }
        let attachmentLimits = OutgoingAttachmentLimits.currentLimits()

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            title: OWSLocalizedString(
                "ATTACHMENT_PASTING",
                comment: "Displayed in a full screen modal when app is processing media that was pasted into message compose field.",
            ),
            asyncBlock: { modal in
                var attachments = [PreviewableAttachment]()
                var firstError: Error?
                for item in items {
                    do {
                        if case .other(let attachment) = try await item.buildAttachment(attachmentLimits: attachmentLimits) {
                            attachments.append(attachment)
                        }
                    } catch {
                        firstError = firstError ?? error
                    }
                }
                let loaded = attachments
                let failure = firstError
                modal.dismiss {
                    if loaded.isEmpty {
                        self.showErrorAlert(attachmentError: failure as? SignalAttachmentError)
                    } else {
                        self.didPasteAttachments(loaded, attachmentLimits: attachmentLimits)
                    }
                }
            },
        )
    }
}

#endif
