// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Tappable button that starts the redirect-based sign-in flow (spec §8.4 Actions).
public struct SignInButton: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let accessibilityIdentifier: String?
    public let onTap: (() -> Void)?

    public init(accessibilityIdentifier: String? = nil, onTap: (() -> Void)? = nil) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
    }

    public var body: some View {
        BaseSignInButton(
            label: i18n.resolve("signIn.button"),
            isLoading: state.isLoading,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            onTap?()
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseSignInButton: View {
    public let label: String
    public let isLoading: Bool
    public let accessibilityIdentifier: String?
    public let action: () -> Void

    public init(
        label: String,
        isLoading: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isLoading = isLoading
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: isLoading ? {} : action) {
            Text(label)
        }
        .disabled(isLoading)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .frame(minWidth: 44, minHeight: 44)
    }
}
