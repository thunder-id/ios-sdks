/// ThunderSwiftUI — Core Lib SDK for iOS / macOS (spec §2.5).
///
/// Drop-in SwiftUI components for ThunderID identity management.
/// Depends on the ThunderID iOS Platform SDK; never imports UIKit.
///
/// Usage:
/// ```swift
/// import ThunderSwiftUI
///
/// @main struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .thunderIDProvider(config: ThunderIDConfig(baseUrl: "...", clientId: "..."))
///         }
///     }
/// }
/// ```
@_exported import ThunderID
