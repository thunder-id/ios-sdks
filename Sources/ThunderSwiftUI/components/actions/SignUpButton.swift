import SwiftUI

/// Button that initiates the sign-up flow (spec §8.4 Actions).
public struct SignUpButton: View {
    @EnvironmentObject private var i18n: ThunderI18n
    public let onTap: (() -> Void)?

    public init(onTap: (() -> Void)? = nil) { self.onTap = onTap }

    public var body: some View {
        BaseSignUpButton(label: i18n.resolve("signUp.button")) { onTap?() }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignUpButton: View {
    public let label: String
    public let action: () -> Void

    public init(label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
        }
        .accessibilityLabel(label)
        .frame(minWidth: 44, minHeight: 44)
    }
}
