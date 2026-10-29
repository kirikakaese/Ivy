//
// Copyright 2026 kiri
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UserNotifications

/// Ivy's push relay wakes Ivy with an alert push, which Apple shows unless
/// the notification service replaces its content. Signal hides its wake-ups
/// with the notification filtering entitlement, which Ivy doesn't have.
///
/// So while the notification service handles a wake-up, the first message
/// notification isn't posted on its own: it becomes the wake-up's content,
/// and the user sees one notification, right away. Further messages from the
/// same wake-up are posted as usual.
public final class IvyWakeCapture {

    public static let shared = IvyWakeCapture()

    private struct State {
        var isCapturing = false
        var captured: UNNotificationContent?
    }

    private let state = AtomicValue(State(), lock: .init())

    /// Starts capturing for one wake-up, in the notification service.
    public func begin() {
        state.set(State(isCapturing: true, captured: nil))
    }

    /// Ends the wake-up and returns the captured notification, if any.
    public func end() -> UNNotificationContent? {
        state.swap(State()).captured
    }

    /// The captured notification so far, for when time runs out.
    public var captured: UNNotificationContent? {
        state.get().captured
    }

    /// Takes the notification as the wake-up's content if a wake-up is
    /// being handled and nothing was taken yet. Returns whether it did.
    func take(_ content: UNNotificationContent) -> Bool {
        state.update { state in
            guard state.isCapturing, state.captured == nil else {
                return false
            }
            state.captured = content
            return true
        }
    }
}
