//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import os
import QuartzCore

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

    // MARK: - Work that ends later

    /// Times something that ends in another call, such as opening a chat
    /// until its messages show. Logged when it took longer than `slowerThan`.
    public struct Interval {
        fileprivate let name: StaticString
        fileprivate let start: UInt64
        fileprivate let state: OSSignpostIntervalState
        fileprivate let threshold: TimeInterval

        public func end() {
            IvyPerformance.signposter.endInterval(name, state)
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            if seconds > threshold {
                Logger.info("Slow: \(name) took \(Int(seconds * 1000)) ms")
            }
        }
    }

    /// Opening a chat, from the click until its messages show. Main thread
    /// only.
    public static var openChat: Interval?

    public static func begin(_ name: StaticString, slowerThan threshold: TimeInterval = slowThreshold) -> Interval {
        Interval(
            name: name,
            start: DispatchTime.now().uptimeNanoseconds,
            state: signposter.beginInterval(name),
            threshold: threshold,
        )
    }
}

// MARK: - Scrolling

/// Counts the frames a list drops while it scrolls. A list calls `scrolled`
/// from `scrollViewDidScroll`; shortly after the scrolling stops, the debug
/// log gets one line if frames were late, for example
/// "Slow: chat scroll dropped 7 of 240 frames, longest 68 ms".
public final class IvyScrollHitches: NSObject {

    public static let shared = IvyScrollHitches()

    /// Scrolling counts as over after this long without movement.
    private static let idleTime: CFTimeInterval = 0.3

    private var displayLink: CADisplayLink?
    private var name: StaticString = ""
    private var lastScroll: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0
    private var frames = 0
    private var dropped = 0
    private var longest: CFTimeInterval = 0

    /// Main thread only.
    public func scrolled(_ name: StaticString) {
        lastScroll = CACurrentMediaTime()
        guard displayLink == nil else { return }
        self.name = name
        lastFrame = 0
        frames = 0
        dropped = 0
        longest = 0
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func frame(_ displayLink: CADisplayLink) {
        let expected = displayLink.targetTimestamp - displayLink.timestamp
        if lastFrame > 0, expected > 0 {
            let elapsed = displayLink.timestamp - lastFrame
            frames += 1
            // Half a frame of slack: timestamps jitter a little.
            if elapsed > expected * 1.5 {
                let missed = Int((elapsed / expected).rounded()) - 1
                dropped += missed
                frames += missed
                longest = max(longest, elapsed)
            }
        }
        lastFrame = displayLink.timestamp

        if CACurrentMediaTime() - lastScroll > Self.idleTime {
            displayLink.invalidate()
            self.displayLink = nil
            if dropped > 0 {
                Logger.info("Slow: \(name) dropped \(dropped) of \(frames) frames, longest \(Int(longest * 1000)) ms")
            }
        }
    }
}
