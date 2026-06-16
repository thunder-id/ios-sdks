import SwiftUI
import ThunderID

/// ViewModifier that injects ThunderState into the environment (spec §7.2).
struct ThunderProviderModifier: ViewModifier {
    let config: ThunderIDConfig
    @StateObject private var state: ThunderState

    init(config: ThunderIDConfig, i18n: ThunderI18n) {
        self.config = config
        _state = StateObject(wrappedValue: ThunderState(client: ThunderClient(), i18n: i18n))
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
    func thunderIDProvider(config: ThunderIDConfig, i18n: ThunderI18n = ThunderI18n()) -> some View {
        modifier(ThunderProviderModifier(config: config, i18n: i18n))
    }
}
