//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

/// A small symbol in a message's footer: the bell when the message has a
/// reminder, the star when it is starred.
final class ReminderMessageIconView: ManualLayoutView {
    private let imageView = CVImageView()
    static let size: CGSize = .square(12)

    init() {
        super.init(name: "ReminderMessageIconView")

        imageView.contentMode = .scaleAspectFit
        addSubviewToFillSuperviewEdges(imageView)
    }

    func configure(tintColor: UIColor, systemName: String = "bell.fill") {
        imageView.image = UIImage(systemName: systemName)
        imageView.tintColor = tintColor
    }
}
