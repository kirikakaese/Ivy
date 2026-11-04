//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class ContextMenuActionsAccessory: ContextMenuTargetedPreviewAccessory, ContextMenuActionsViewDelegate {

    public let menu: ContextMenu

    private let menuView: ContextMenuActionsView

    private let minimumScale: CGFloat = 0.2
    private let minimumOpacity: CGFloat = 0.2
    private let springDamping: CGFloat = 0.8
    private let springInitialVelocity: CGFloat = 1

    public init(
        menu: ContextMenu,
        accessoryAlignment: AccessoryAlignment,
        forceDarkTheme: Bool = false,
    ) {
        self.menu = menu

        menuView = ContextMenuActionsView(menu: menu)
        if forceDarkTheme {
            menuView.overrideUserInterfaceStyle = .dark
        }
        menuView.isHidden = true
        super.init(accessoryView: menuView, accessoryAlignment: accessoryAlignment)
        menuView.delegate = self
        animateAccessoryPresentationAlongsidePreview = true
    }

    override func animateIn(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void,
    ) {

        setMenuLayerAnchorPoint()

        menuView.transform = CGAffineTransform.scale(minimumScale)
        menuView.isHidden = false
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: springDamping,
            initialSpringVelocity: springInitialVelocity,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.menuView.transform = CGAffineTransform.identity
            },
            completion: nil,
        )

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = minimumOpacity
        opacityAnimation.toValue = 1
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        menuView.layer.add(opacityAnimation, forKey: "insertOpacity")
    }

    override func animateOut(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void,
    ) {

        setMenuLayerAnchorPoint()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.menuView.transform = CGAffineTransform.scale(self.minimumScale)
            },
            completion: { _ in
                completion()
            },
        )

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1
        opacityAnimation.toValue = 0
        opacityAnimation.duration = duration - 0.1
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        opacityAnimation.isRemovedOnCompletion = false
        opacityAnimation.fillMode = .forwards
        menuView.layer.add(opacityAnimation, forKey: "removeOpacity")
    }

    private func setMenuLayerAnchorPoint() {
        let previewAlignment = delegate?.contextMenuTargetedPreviewAccessoryPreviewAlignment(self)
        let xAnchor: CGFloat
        switch previewAlignment {
        case .center:
            xAnchor = 0.5
        case .left:
            xAnchor = 0
        case .right:
            xAnchor = 1
        case .none:
            xAnchor = 0
        }

        var yAnchor: CGFloat = 0
        alignments: for accessoryAlignment in accessoryAlignment.alignments {
            switch accessoryAlignment {
            case (.top, .exterior):
                yAnchor = 1
                break alignments
            case (.bottom, .exterior):
                yAnchor = 0
                break alignments
            default:
                break
            }
        }

        let frame = menuView.frame
        menuView.layer.anchorPoint = CGPoint(x: xAnchor, y: yAnchor)
        menuView.frame = frame
    }

    override func touchLocationInViewDidChange(
        locationInView: CGPoint,
    ) {
        menuView.handleGestureChanged(locationInView: locationInView)
    }

    override func touchLocationInViewDidEnd(
        locationInView: CGPoint,
    ) -> Bool {
        return menuView.handleGestureEnded(locationInView: locationInView)
    }

    func contextMenuActionViewDidSelectAction(contextMenuAction: ContextMenuAction) {
        delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self, completion: {
            contextMenuAction.handler(contextMenuAction)
        })
    }
}

protocol ContextMenuActionsViewDelegate: AnyObject {
    func contextMenuActionViewDidSelectAction(contextMenuAction: ContextMenuAction)
}

private class ContextMenuActionsView: UIView, UIGestureRecognizerDelegate, UIScrollViewDelegate {

    private class ContextMenuActionRow: UIView {
        let attributes: ContextMenuAction.Attributes
        let titleLabel: UILabel
        let iconView: UIImageView
        var separatorView: UIView?
        var highlightedView: UIView?
        var isHighlighted: Bool {
            didSet {
                if oldValue != isHighlighted {
                    if isHighlighted {
                        if highlightedView == nil {
                            let view = UIView()

                            if #available(iOS 26, *) {
                                view.frame = bounds.insetBy(dx: 10, dy: 1)
                                view.cornerConfiguration = .capsule()
                            } else {
                                view.frame = bounds
                            }

                            view.backgroundColor = .Signal.secondaryFill
                            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                            highlightedView = view
                        }

                        if let view = highlightedView {
                            insertSubview(view, at: 1)
                        }
                    } else {
                        highlightedView?.removeFromSuperview()
                    }
                }
            }
        }

        var maxWidth: CGFloat = 250
        let margin: CGFloat = if #available(iOS 26, *) {
            24
        } else {
            16
        }

        let iconSpacing: CGFloat = 12
        let verticalPadding: CGFloat = 23
        let iconSize: CGFloat = if #available(iOS 26, *) {
            24
        } else {
            20
        }

        let titleMaxLines = 2

        init(
            title: String,
            icon: UIImage?,
            attributes: ContextMenuAction.Attributes,
            hostBlurEffect: UIBlurEffect?,
        ) {
            titleLabel = UILabel(frame: CGRect.zero)
            titleLabel.text = title
            titleLabel.font = .dynamicTypeBodyClamped
            titleLabel.numberOfLines = titleMaxLines

            self.attributes = attributes

            /// when made a child of a UIVisualEffectView, UILabel text color is overridden, but a vibrancy effect is added.
            /// When we aren't using a color anyway, we want the vibrancy effect so we add it as a subview of the visual effect.
            /// If we want the colors to take effect, however, we make it a subview of the root view.
            let makeLabelSubviewOfVisualEffectsView: Bool
            if attributes.contains(.destructive) {
                titleLabel.textColor = .Signal.red
                makeLabelSubviewOfVisualEffectsView = false
            } else if attributes.contains(.disabled) {
                titleLabel.textColor = .Signal.secondaryLabel
                makeLabelSubviewOfVisualEffectsView = false
            } else {
                titleLabel.textColor = .Signal.label
                makeLabelSubviewOfVisualEffectsView = true
            }

            iconView = UIImageView(image: icon)
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = titleLabel.textColor

            isHighlighted = false

            super.init(frame: .zero)

            if let hostBlurEffect {
                let visualEffectView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: hostBlurEffect, style: .label))
                addSubview(visualEffectView)
                if makeLabelSubviewOfVisualEffectsView {
                    visualEffectView.contentView.addSubview(titleLabel)
                } else {
                    addSubview(titleLabel)
                }

                let separatorView = UIView()
                separatorView.backgroundColor = .Signal.transparentSeparator
                separatorView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.separatorView = separatorView

                visualEffectView.contentView.addSubview(iconView)
                visualEffectView.contentView.addSubview(separatorView)

                visualEffectView.autoPinEdgesToSuperviewEdges()
            } else {
                addSubview(titleLabel)
                addSubview(iconView)
            }

            isAccessibilityElement = true
            accessibilityLabel = titleLabel.text
            accessibilityTraits = .button
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let isRTL = CurrentAppContext().isRTL
            titleLabel.sizeToFit()
            var titleFrame = titleLabel.frame
            var iconViewFrame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)

            titleFrame.y = ceil((bounds.height - titleFrame.height) / 2)
            iconViewFrame.y = max(0, (bounds.height - iconViewFrame.height) / 2)

            let titleWidth = bounds.width - iconViewFrame.width - (2 * margin) - iconSpacing
            if titleWidth < titleFrame.width {
                // Give it more height for a second line.
                let originalHeight = titleLabel.textRect(forBounds: CGRect.infinite, limitedToNumberOfLines: 1).height
                let multiLineHeight = titleLabel.textRect(
                    forBounds: CGRect(
                        origin: .zero,
                        size: .init(width: titleWidth, height: .infinity),
                    ),
                    limitedToNumberOfLines: titleMaxLines,
                ).height
                let extraHeight = multiLineHeight - originalHeight
                titleFrame.origin.y -= extraHeight / 2
                titleFrame.height += extraHeight
            }
            titleFrame.width = titleWidth

            let iconIsToTheRightOfText = if #available(iOS 26, *) {
                isRTL
            } else {
                !isRTL
            }

            if iconIsToTheRightOfText {
                titleFrame.x = margin
                iconViewFrame.x = titleFrame.maxX + iconSpacing
            } else {
                iconViewFrame.x = margin
                titleFrame.x = iconViewFrame.maxX + iconSpacing
            }

            titleLabel.frame = titleFrame
            iconView.frame = iconViewFrame

            if let separatorView {
                var separatorFrame = bounds
                separatorFrame.height = hairlineWidth
                separatorFrame.y = bounds.maxY - separatorFrame.height
                separatorView.frame = separatorFrame
            }
        }

        override func sizeThatFits(
            _ size: CGSize,
        ) -> CGSize {
            let height = ceil(titleLabel.sizeThatFits(CGSize(width: maxWidth - (2 * margin) - iconSpacing - iconSize, height: 0)).height) + verticalPadding
            return CGSize(width: maxWidth, height: height)
        }
    }

    // Ivy: an everyday action as an icon with a short title, in a row on top.
    private final class IvyIconCell: UIView {
        static let height: CGFloat = 62
        let action: ContextMenuAction
        private let iconView = UIImageView()
        private let label = UILabel()
        private let highlight = UIView()
        var isHighlighted = false {
            didSet { highlight.isHidden = !isHighlighted }
        }

        init(action: ContextMenuAction) {
            self.action = action
            super.init(frame: .zero)
            highlight.backgroundColor = .Signal.secondaryFill
            highlight.layer.cornerRadius = 14
            highlight.layer.cornerCurve = .continuous
            highlight.isHidden = true
            addSubview(highlight)
            iconView.image = action.image
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .Signal.label
            addSubview(iconView)
            label.text = action.title
            label.font = .dynamicTypeCaption2
            label.textColor = .Signal.label
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            addSubview(label)
            isAccessibilityElement = true
            accessibilityLabel = action.title
            accessibilityTraits = .button
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            highlight.frame = bounds.insetBy(dx: 4, dy: 3)
            iconView.frame = CGRect(x: (bounds.width - 24) / 2, y: 10, width: 24, height: 24)
            label.frame = CGRect(x: 2, y: 38, width: bounds.width - 4, height: 16)
        }
    }

    weak var delegate: ContextMenuActionsViewDelegate?
    let menu: ContextMenu

    // Ivy: the rows can change when "More" opens, so they're kept with
    // their actions.
    private var actionViews: [ContextMenuActionRow]
    private var rowActions: [ContextMenuAction]
    private var ivyIconCells: [IvyIconCell]
    private let ivyIconSeparator = UIView()
    private let ivyHostBlurEffect: UIBlurEffect?
    private var ivyBackAction: ContextMenuAction?
    private let scrollView: UIScrollView
    private let backdropView: UIVisualEffectView

    private var tapGestureRecognizer: UILongPressGestureRecognizer?
    private var highlightHoverGestureRecognizer: UIGestureRecognizer?

    var isScrolling: Bool {
        didSet {
            if isScrolling, oldValue != isScrolling {
                for actionRow in actionViews {
                    actionRow.isHighlighted = false
                }
            }
        }
    }

    let cornerRadius: CGFloat = if #available(iOS 26, *) {
        33
    } else {
        12
    }

    let vMargin: CGFloat = if #available(iOS 26, *) {
        10
    } else {
        0
    }

    init(menu: ContextMenu) {
        self.menu = menu

        scrollView = UIScrollView(frame: CGRect.zero)
        scrollView.verticalScrollIndicatorInsets = .init(hMargin: 0, vMargin: cornerRadius)

        let blurEffect: UIBlurEffect?
        if #available(iOS 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            backdropView = UIVisualEffectView(effect: effect)
            blurEffect = nil
        } else {
            blurEffect = UIBlurEffect(style: .systemMaterial)
            backdropView = UIVisualEffectView(effect: blurEffect)
        }

        self.actionViews = Self.ivyRows(for: menu.children, hostBlurEffect: blurEffect)
        self.rowActions = menu.children
        self.ivyIconCells = menu.ivyIconRow.map { IvyIconCell(action: $0) }
        self.ivyHostBlurEffect = blurEffect
        isScrolling = false

        super.init(frame: CGRect.zero)

        let tapGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tapGestureRecognized(sender:)))
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.minimumPressDuration = 0

        addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer

        let highlightHoverGestureRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(hoverGestureRecognized(sender:)))
        highlightHoverGestureRecognizer.delegate = self
        addGestureRecognizer(highlightHoverGestureRecognizer)
        self.highlightHoverGestureRecognizer = highlightHoverGestureRecognizer

        if #unavailable(iOS 26) {
            layer.cornerRadius = cornerRadius
            layer.shadowRadius = 64
            layer.shadowOffset = CGSize(width: 0, height: 32)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.2
        }

        backdropView.layer.cornerRadius = cornerRadius
        backdropView.layer.masksToBounds = true
        addSubview(backdropView)
        backdropView.contentView.addSubview(scrollView)

        for actionView in actionViews {
            scrollView.addSubview(actionView)
        }
        for cell in ivyIconCells {
            scrollView.addSubview(cell)
        }
        ivyIconSeparator.backgroundColor = .Signal.transparentSeparator
        ivyIconSeparator.isHidden = ivyIconCells.isEmpty
        scrollView.addSubview(ivyIconSeparator)

        scrollView.delegate = self

        actionViews.last?.separatorView?.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIView

    override func layoutSubviews() {
        super.layoutSubviews()

        backdropView.frame = bounds
        scrollView.frame = bounds
        var yOffset: CGFloat = vMargin
        var maxY: CGFloat = 0
        var width: CGFloat = 0.0
        // Ivy: the icon row first, across the menu's width.
        if !ivyIconCells.isEmpty {
            let rowWidth = actionViews.map { $0.sizeThatFits(.zero).width }.max() ?? Self.ivyIconRowWidth
            let cellWidth = rowWidth / CGFloat(ivyIconCells.count)
            let isRTL = CurrentAppContext().isRTL
            for (index, cell) in ivyIconCells.enumerated() {
                let position = isRTL ? ivyIconCells.count - 1 - index : index
                cell.frame = CGRect(x: CGFloat(position) * cellWidth, y: yOffset, width: cellWidth, height: IvyIconCell.height)
            }
            yOffset += IvyIconCell.height
            ivyIconSeparator.frame = CGRect(x: 0, y: yOffset - hairlineWidth, width: rowWidth, height: hairlineWidth)
            maxY = yOffset
        }
        for actionView in actionViews {
            let size = actionView.sizeThatFits(.zero)
            width = max(width, size.width)
            actionView.frame = CGRect(x: 0, y: yOffset, width: width, height: size.height)
            yOffset += size.height
            maxY = max(maxY, actionView.frame.maxY)
        }
        maxY += vMargin

        scrollView.contentSize = CGSize(width: width, height: maxY)
    }

    override func sizeThatFits(
        _ size: CGSize,
    ) -> CGSize {
        // every entry may have a different height
        var height = vMargin * 2 + (ivyIconCells.isEmpty ? 0 : IvyIconCell.height) // Ivy: the icon row
        var width = 0.0
        for actionView in actionViews {
            let size = actionView.sizeThatFits(size)
            height += size.height
            width = max(width, size.width)
        }
        if !ivyIconCells.isEmpty {
            width = max(width, Self.ivyIconRowWidth) // Ivy: room for the icons
        }
        return CGSize(width: width, height: height)
    }

    // MARK: Gestures

    @objc
    private func tapGestureRecognized(sender: UIGestureRecognizer) {
        if sender.state == .began || sender.state == .changed {
            handleGestureChanged(locationInView: sender.location(in: scrollView))
        } else if sender.state == .ended {
            handleGestureEnded(locationInView: sender.location(in: scrollView))
        }
    }

    @objc
    private func hoverGestureRecognized(sender: UIGestureRecognizer) {
        if sender.state == .began || sender.state == .changed {
            handleGestureChanged(locationInView: sender.location(in: scrollView))
        } else if sender.state == .ended {
            for actionRow in actionViews {
                actionRow.isHighlighted = false
            }
        }
    }

    func handleGestureChanged(locationInView: CGPoint) {
        guard !isScrolling else {
            return
        }

        // Add impact effect here
        var highlightStateChanged = false
        // Ivy: the icon row reacts like the rows.
        for cell in ivyIconCells {
            let wasHighlighted = cell.isHighlighted
            cell.isHighlighted = cell.frame.contains(locationInView) && !cell.action.attributes.contains(.disabled)
            if wasHighlighted != cell.isHighlighted {
                highlightStateChanged = true
            }
        }
        for actionRow in actionViews {
            let wasHighlighted = actionRow.isHighlighted
            let shouldHighlight = actionRow.frame.contains(locationInView) && !actionRow.attributes.contains(.disabled)
            actionRow.isHighlighted = shouldHighlight

            if !highlightStateChanged {
                highlightStateChanged = wasHighlighted != shouldHighlight
            }
        }

        if highlightStateChanged {
            ImpactHapticFeedback.impactOccurred(style: .light)
        }
    }

    @discardableResult
    func handleGestureEnded(locationInView: CGPoint) -> Bool {
        guard !isScrolling else {
            return false
        }

        // Ivy: an icon in the row on top.
        if let cell = ivyIconCells.first(where: { $0.isHighlighted }) {
            ivyIconCells.forEach { $0.isHighlighted = false }
            delegate?.contextMenuActionViewDidSelectAction(contextMenuAction: cell.action)
            return true
        }

        var index: Int = NSNotFound
        for (rowIndex, actionRow) in actionViews.enumerated() {
            if actionRow.isHighlighted, index == NSNotFound {
                index = rowIndex
            }
            actionRow.isHighlighted = false
        }

        if index != NSNotFound {
            let action = rowActions[index]
            // Ivy: "More" opens its actions in place; "Back" returns.
            if let submenu = action.ivySubmenu {
                ivyShowRows(submenu, withBack: true)
                return true
            }
            if action === ivyBackAction {
                ivyShowRows(menu.children, withBack: false)
                return true
            }
            delegate?.contextMenuActionViewDidSelectAction(contextMenuAction: action)
            return true
        }

        return false
    }

    // MARK: Ivy

    private static let ivyIconRowWidth: CGFloat = 250

    private static func ivyRows(for actions: [ContextMenuAction], hostBlurEffect: UIBlurEffect?) -> [ContextMenuActionRow] {
        let rows = actions.map { action in
            ContextMenuActionRow(
                title: action.title,
                icon: action.image,
                attributes: action.attributes,
                hostBlurEffect: hostBlurEffect,
            )
        }
        rows.last?.separatorView?.isHidden = true
        return rows
    }

    /// Swaps the rows: the actions under "More" with a "Back" row on top,
    /// or the menu's own rows again. The menu resizes in place.
    private func ivyShowRows(_ actions: [ContextMenuAction], withBack: Bool) {
        var shown = actions
        if withBack {
            let back = ContextMenuAction(
                title: IvyLocalizedString("MESSAGE_MENU_BACK", comment: "Row at the top of the message menu's More actions that goes back to the main actions."),
                image: UIImage(systemName: CurrentAppContext().isRTL ? "chevron.right" : "chevron.left"),
                handler: { _ in },
            )
            ivyBackAction = back
            shown.insert(back, at: 0)
        } else {
            ivyBackAction = nil
        }
        actionViews.forEach { $0.removeFromSuperview() }
        actionViews = Self.ivyRows(for: shown, hostBlurEffect: ivyHostBlurEffect)
        rowActions = shown
        actionViews.forEach { scrollView.addSubview($0) }
        ivyIconCells.forEach { $0.isHidden = withBack }
        if withBack {
            ivyIconCells.forEach { $0.removeFromSuperview() }
        } else {
            ivyIconCells = menu.ivyIconRow.map { IvyIconCell(action: $0) }
            ivyIconCells.forEach { scrollView.addSubview($0) }
        }
        ivyIconSeparator.isHidden = ivyIconCells.isEmpty || withBack
        if withBack {
            ivyIconCells = []
        }
        ImpactHapticFeedback.impactOccurred(style: .light)
        setNeedsLayout()
        superview?.setNeedsLayout()
        UIView.animate(withDuration: 0.25) {
            self.superview?.layoutIfNeeded()
            self.layoutIfNeeded()
        }
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isScrolling = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isScrolling = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isScrolling = false
    }

}
