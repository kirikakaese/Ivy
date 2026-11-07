//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import os

/// Times Ivy's own work on paths that run often (the chat list, Home,
/// switching sections, launch). Anything slower than a frame goes to the
/// local debug log, so a log sent with Report a Problem shows where Ivy
/// stalls; Instruments shows every interval as a signpost.
public enum IvyPerformance {

    /// Longer than this is logged: a frame at 60 Hz.
    public static let slowThreshold: TimeInterval = 1.0 / 60

    private static let signposter = OSSignposter(subsystem: "io.github.kirikakaese.ivy", category: "Performance")

    @discardableResult
    public static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let interval = signposter.beginInterval(name)
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            signposter.endInterval(name, interval)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            if seconds > slowThreshold {
                Logger.info("Slow: \(name) took \(Int(seconds * 1000)) ms\(Thread.isMainThread ? " on the main thread" : "")")
            }
        }
        return try work()
    }
}
