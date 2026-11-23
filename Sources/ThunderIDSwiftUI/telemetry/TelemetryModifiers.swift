// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Combine
import SwiftUI
import ThunderID

/// Reports a screen view each time the view appears. A screen that appears before the SDK is initialized is
/// reported once it is, since telemetry starts during initialization.
struct TelemetryScreenModifier: ViewModifier {
    let pattern: String
    @Environment(\.thunderState) private var state
    /// Whether the view appeared before the SDK was initialized and has not been reported yet.
    @State private var waitingForInitialization = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard let state else { return }
                if state.isInitialized {
                    state.client.trackPageView(pattern)
                } else {
                    waitingForInitialization = true
                }
            }
            .onDisappear { waitingForInitialization = false }
            .onReceive(initialized) { ready in
                guard ready, waitingForInitialization, let state else { return }
                waitingForInitialization = false
                state.client.trackPageView(pattern)
            }
    }

    private var initialized: AnyPublisher<Bool, Never> {
        state?.$isInitialized.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }
}

/// Reports each link opened through `openURL` below it, then opens it as it would have been opened. Below
/// another such modifier it does nothing, so a link is reported once.
struct TelemetryLinksModifier: ViewModifier {
    @Environment(\.thunderState) private var state
    @Environment(\.openURL) private var openURL
    @Environment(\.telemetryLinksReported) private var reportedAbove

    func body(content: Content) -> some View {
        if reportedAbove {
            content
        } else {
            content
                .environment(\.openURL, OpenURLAction { url in
                    state?.client.trackLink(url)
                    openURL(url)
                    return .handled
                })
                .environment(\.telemetryLinksReported, true)
        }
    }
}

/// Whether a `telemetryLinks()` modifier above already reports the links opened below it.
private struct TelemetryLinksReportedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var telemetryLinksReported: Bool {
        get { self[TelemetryLinksReportedKey.self] }
        set { self[TelemetryLinksReportedKey.self] = newValue }
    }
}

public extension View {
    /// Reports a screen view, named from `pattern`, each time this view appears. Pass the screen's route
    /// pattern, such as `applications/:id`, never a URL or the ids in it. Does nothing while telemetry is off.
    ///
    /// ```swift
    /// ApplicationDetails(id: id)
    ///     .telemetryScreen("applications/:id")
    /// ```
    func telemetryScreen(_ pattern: String) -> some View {
        modifier(TelemetryScreenModifier(pattern: pattern))
    }

    /// Reports the links opened below this view through SwiftUI's `openURL`, such as a `Link` or a link in
    /// `Text`, as `link.open` with their host and path only, then opens each as it would have been opened.
    /// Apply it inside `thunderIDProvider`. Does nothing while telemetry is off.
    func telemetryLinks() -> some View {
        modifier(TelemetryLinksModifier())
    }
}
