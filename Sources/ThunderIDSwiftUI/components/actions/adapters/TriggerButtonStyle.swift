// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Shared outlined-button chrome for `eventType: TRIGGER` (federated login) actions: an icon
/// slot, a label, and a rounded-rect stroke — matching the "Continue with X" buttons rendered
/// below a SignIn form's "Or" divider.
struct TriggerButtonStyle<Icon: View>: View {
    let label: String
    let isLoading: Bool
    /// Disables the button without showing a spinner, e.g. while a sibling button's
    /// submission is in flight.
    var disabled: Bool = false
    let onTap: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: (isLoading || disabled) ? {} : onTap) {
            HStack(spacing: 10) {
                icon
                Text(label)
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .foregroundColor(.primary)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4), lineWidth: 1))
        .disabled(isLoading || disabled)
        .accessibilityLabel(label)
    }
}

/// Generic outlined trigger button for TRIGGER actions with no dedicated brand adapter,
/// using the label supplied by the flow schema.
struct GenericTriggerButton: View {
    let label: String
    let isLoading: Bool
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        TriggerButtonStyle(label: label, isLoading: isLoading, disabled: disabled, onTap: onTap) {
            EmptyView()
        }
    }
}
