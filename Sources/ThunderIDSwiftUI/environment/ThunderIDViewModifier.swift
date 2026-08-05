// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// ViewModifier that injects ThunderIDState into the environment (spec §7.2).
struct ThunderIDProviderModifier: ViewModifier {
    let config: ThunderIDConfig
    @StateObject private var state: ThunderIDState

    init(config: ThunderIDConfig, i18n: ThunderIDI18n) {
        self.config = config
        _state = StateObject(wrappedValue: ThunderIDState(client: ThunderIDClient(), i18n: i18n))
    }

    func body(content: Content) -> some View {
        content
            .environment(\.thunderState, state)
            .environmentObject(state)
            .environmentObject(state.i18n)
            .task { await state.initialize(config: config) }
    }
}

public extension View {
    /// Injects ThunderID auth state into the SwiftUI environment.
    ///
    /// ```swift
    /// ContentView()
    ///     .thunderIDProvider(config: ThunderIDConfig(baseUrl: "...", clientId: "..."))
    /// ```
    func thunderIDProvider(config: ThunderIDConfig, i18n: ThunderIDI18n? = nil) -> some View {
        let resolvedI18n = i18n ?? ThunderIDI18n(storageKey: "\(config.vendor)_locale")
        return modifier(ThunderIDProviderModifier(config: config, i18n: resolvedI18n))
    }
}
