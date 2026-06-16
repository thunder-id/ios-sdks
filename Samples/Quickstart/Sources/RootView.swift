import SwiftUI
import ThunderSwiftUI

struct RootView: View {
    @EnvironmentObject private var state: ThunderState

    var body: some View {
        if !state.isInitialized || state.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Starting ACME Booking\u{2026}")
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
