// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Tracks when an embedded flow execution expires, and starts the flow again once it has and the app is active.
/// A flow that expires while the app is in the background starts again when the user comes back to it.
@MainActor
final class FlowExpiry {
    /// Starts the flow again.
    var restart: () -> Void = {}

    private let now: () -> Date
    private var deadline: Date?
    private var isExpired = false
    private var isActive = true
    private var timer: Task<Void, Never>?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Tracks the expiry of a step, counted from when its response arrived. A flow that ended, or a step without an
    /// expiry, stops the tracking.
    func track(_ response: EmbeddedFlowResponse) {
        stop()
        guard response.flowStatus == .promptOnly, let expiresIn = response.expiresIn else {
            return
        }
        deadline = now().addingTimeInterval(TimeInterval(expiresIn))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(expiresIn, 0)))
            guard !Task.isCancelled else {
                return
            }
            self?.expire()
        }
    }

    /// Marks the flow as expired, e.g. when the server refused a step as expired.
    func expire() {
        stop()
        isExpired = true
        restartIfActive()
    }

    /// Tells whether the app is active. Coming back checks the deadline again, since the timer may not have run in
    /// the background.
    func setActive(_ active: Bool) {
        isActive = active
        if let deadline, now() >= deadline {
            expire()
        } else {
            restartIfActive()
        }
    }

    /// Stops tracking the current flow.
    func stop() {
        timer?.cancel()
        timer = nil
        deadline = nil
        isExpired = false
    }

    private func restartIfActive() {
        guard isExpired, isActive else {
            return
        }
        isExpired = false
        restart()
    }
}
