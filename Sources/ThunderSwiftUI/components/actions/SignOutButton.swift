import SwiftUI

/// Button that calls signOut and refreshes auth state (spec §8.4 Actions).
public struct SignOutButton: View {
    @EnvironmentObject private var state: ThunderState
    @EnvironmentObject private var i18n: ThunderI18n
    public let onSignOutComplete: (() -> Void)?

    public init(onSignOutComplete: (() -> Void)? = nil) { self.onSignOutComplete = onSignOutComplete }

    public var body: some View {
        BaseSignOutButton(
            label: i18n.resolve("signOut.button"),
            isLoading: state.isLoading
        ) {
            Task {
                _ = try? await state.client.signOut()
                await state.refresh()
                onSignOutComplete?()
            }
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignOutButton: View {
    public let label: String
    public let isLoading: Bool
    public let action: () -> Void

    public init(label: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: isLoading ? {} : action) {
            Text(label)
        }
        .disabled(isLoading)
        .accessibilityLabel(label)
        .frame(minWidth: 44, minHeight: 44)
    }
}
