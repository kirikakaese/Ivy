//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension RemoteMegaphoneModel.Manifest {

    /// Whether the megaphone asks the user to donate. Ivy has no donations, so
    /// it does not show these; other remote megaphones still appear.
    public var asksForDonation: Bool {
        if case .standardDonate = conditionalCheck {
            return true
        }
        return [primaryAction, secondaryAction].contains { action in
            switch action {
            case .donate, .donateFriend:
                return true
            case .finish, .snooze, .unrecognized, nil:
                return false
            }
        }
    }
}
