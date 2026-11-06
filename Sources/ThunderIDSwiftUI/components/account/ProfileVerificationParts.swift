// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// A green Verified or amber Unverified label with its icon.
struct ProfileStatusLabel: View {
    let label: String
    let isVerified: Bool
    let identifier: String
    @Environment(\.colorScheme) private var colorScheme

    init(label: String, isVerified: Bool, identifier: String) {
        self.label = label
        self.isVerified = isVerified
        self.identifier = identifier
    }

    init(field: ProfileField, status: AttributeVerificationStatus, i18n: ThunderIDI18n) {
        let verified = status != .unverified
        self.init(
            label: i18n.resolve(verified ? "verifyAttribute.status.verified" : "verifyAttribute.status.unverified"),
            isVerified: verified,
            identifier: "thunderid-verification-status-\(field.name)"
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isVerified ? "checkmark.circle" : "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(label)
        }
        .accessibilityElement(children: .combine)
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(isVerified ? colorScheme.userProfileVerified : colorScheme.userProfileUnverified)
        .accessibilityIdentifier(identifier)
    }
}

struct ProfileVerifyButton: View {
    let label: String
    let identifier: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.userProfileAccent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
