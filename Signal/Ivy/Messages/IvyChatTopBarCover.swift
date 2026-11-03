//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

/// While a chat slides in, iOS 26 doesn't yet blur the messages behind the
/// top bar, so they show through it. This cover blurs them for the length
/// of the transition and then fades into the system's own blur.
final class IvyChatTopBarCover: UIView {

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let fade = CAGradientLayer()

    /// How far below the top bar the blur fades out.
    static let fadeHeight: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(blur)
        blur.autoPinEdgesToSuperviewEdges()
        fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        layer.mask = fade
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fade.frame = bounds
        let solid = bounds.height > 0 ? max(0, (bounds.height - Self.fadeHeight) / bounds.height) : 0
        fade.locations = [0, NSNumber(value: Double(solid)), 1]
    }
}

extension ConversationViewController {

    /// Covers the top bar while the chat opens. Called from viewWillAppear.
    func ivyCoverTopBarWhileOpening() {
        guard #available(iOS 26, *), !isInPreviewPlatter, let coordinator = transitionCoordinator, coordinator.isAnimated else {
            return
        }
        let cover = IvyChatTopBarCover()
        view.insertSubview(cover, aboveSubview: collectionView)
        cover.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: view.topAnchor),
            cover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: IvyChatTopBarCover.fadeHeight),
        ])
        coordinator.animate(alongsideTransition: nil) { _ in
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) {
                cover.alpha = 0
            } completion: { _ in
                cover.removeFromSuperview()
            }
        }
    }
}
