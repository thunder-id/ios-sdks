/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

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
