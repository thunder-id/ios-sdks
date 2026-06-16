import SwiftUI

/// Tappable button that starts the redirect-based sign-in flow (spec §8.4 Actions).
public struct SignInButton: View {
    @EnvironmentObject private var state: ThunderState
    @EnvironmentObject private var i18n: ThunderI18n
    public let onTap: (() -> Void)?

    public init(onTap: (() -> Void)? = nil) { self.onTap = onTap }

    public var body: some View {
        BaseSignInButton(label: i18n.resolve("signIn.button"), isLoading: state.isLoading) {
            onTap?()
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignInButton: View {
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
