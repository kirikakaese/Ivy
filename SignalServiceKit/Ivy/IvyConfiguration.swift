//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The decisions that make Ivy behave differently from upstream Signal.
///
/// Upstream code refers to these at its `// Ivy:` integration points, so each
/// decision is made in one place.
public enum IvyConfiguration {

    /// Signal's servers send Apple push notifications only to the official
    /// app. Ivy registers without a push token, keeps a connection open while
    /// it runs and fetches messages in the background where the system allows.
    public static let usesApplePushNotifications = false

    /// Without push notifications, the Mac keeps the connection open while
    /// Ivy runs, also when none of its windows is active. iOS suspends apps in
    /// the background, so there the connection follows the app state.
    /// How often iOS should give Ivy a chance to fetch messages in the
    /// background. The system treats this as the earliest time and decides
    /// itself when the app actually runs.
    public static let backgroundRefreshInterval: TimeInterval = 15 * 60

    /// Ivy has no Stories, Payments or donations. These switches hide them
    /// in the interface only: the account settings that Signal syncs between
    /// devices (for example "stories enabled" or the payment address in the
    /// profile) are left unchanged, so other devices are not affected.
    public static let showsStories = false
    public static let showsPayments = false
    public static let showsDonations = false

    /// Signal's paid backup plan is an App Store purchase of Signal's own
    /// app. Ivy uses the plan the account has, but can't see, renew or
    /// manage that purchase; that stays in Signal.
    public static let managesBackupSubscription = false

    /// Debug logs stay on the device. The user can export them and share
    /// them with whoever they choose; they are never uploaded to Signal.
    public static let uploadsDebugLogs = false

    /// Shown on the About screen.
    public static let maintainer = "kiri"
    public static let sourceCodeURL = URL(string: "https://github.com/kirikakaese/Ivy")!
    public static let licenseURL = URL(string: "https://github.com/kirikakaese/Ivy/blob/main/LICENSE")!
    /// Ivy is not supported by Signal, so problems are reported here.
    public static let issuesURL = URL(string: "https://github.com/kirikakaese/Ivy/issues")!

    public static var keepsConnectionWhileInactive: Bool {
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }
}
