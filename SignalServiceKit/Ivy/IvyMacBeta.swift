//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The Mac beta: a build signed ad hoc, for use before Ivy has a developer
/// certificate (built with `Scripts/ivy/mac-beta.sh`, compilation condition
/// `IVY_MAC_BETA`).
///
/// macOS grants an app group container and keychain sharing only to apps
/// with a certificate, so the beta keeps its data in its own folder and its
/// keys in the login keychain. It has no extensions.
public enum IvyMacBeta {

    public static var isEnabled: Bool {
#if IVY_MAC_BETA
        return true
#else
        return false
#endif
    }

    /// `~/Library/Application Support/Ivy Beta`, used in place of the app
    /// group container.
    public static var dataDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ivy Beta", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
