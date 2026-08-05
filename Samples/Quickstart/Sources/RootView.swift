// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

struct RootView: View {
    @EnvironmentObject private var state: ThunderIDState

    var body: some View {
        if !state.isInitialized || state.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading\u{2026}")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.error {
            VStack(spacing: 16) {
                Text("Configuration error: \(error)\n\nCheck your .env values.")
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.isSignedIn {
            HomeView()
        } else {
            AuthView()
        }
    }
}
