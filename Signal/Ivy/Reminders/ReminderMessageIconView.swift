//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

/// The bell in a message's footer when the message has a reminder.
final class ReminderMessageIconView: ManualLayoutView {
    private let imageView = CVImageView()
    static let size: CGSize = .square(12)

    init() {
        super.init(name: "ReminderMessageIconView")

        imageView.contentMode = .scaleAspectFit
        addSubviewToFillSuperviewEdges(imageView)
    }

    func configure(tintColor: UIColor) {
        imageView.image = UIImage(systemName: "bell.fill")
        imageView.tintColor = tintColor
    }
}
