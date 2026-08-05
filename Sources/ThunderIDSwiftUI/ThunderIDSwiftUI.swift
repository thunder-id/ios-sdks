// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// ThunderIDSwiftUI — Core Lib SDK for iOS / macOS (spec §2.5).
///
/// Drop-in SwiftUI components for ThunderID identity management.
/// Depends on the ThunderID iOS Platform SDK; never imports UIKit.
///
/// Usage:
/// ```swift
/// import ThunderIDSwiftUI
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
