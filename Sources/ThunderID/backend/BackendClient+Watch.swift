// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension BackendClient {
    /// Watches for the session ending while the app runs: checks it whenever the app comes back to the
    /// foreground, and every `pollInterval` seconds when that is positive.
    func startWatching(pollInterval: TimeInterval) {
        stopWatching()
        if let name = Self.foregroundNotification {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { await self?.checkOnForeground() }
            }
        }
        guard pollInterval > 0 else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.checkIfSignedIn()
            }
        }
    }

    func stopWatching() {
        pollTask?.cancel()
        pollTask = nil
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        foregroundObserver = nil
    }

    private func checkOnForeground() async {
        guard Date().timeIntervalSince(lastCheck) >= Self.foregroundCheckThrottle else { return }
        await checkIfSignedIn()
    }

    private func checkIfSignedIn() async {
        guard tokenStore.sessionHandle() != nil else { return }
        await checkSession()
    }

    private static var foregroundNotification: Notification.Name? {
        #if canImport(UIKit)
        return UIApplication.willEnterForegroundNotification
        #elseif canImport(AppKit)
        return NSApplication.didBecomeActiveNotification
        #else
        return nil
        #endif
    }
}
