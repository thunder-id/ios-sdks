// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension ThunderIDI18n {
    /// The message for a sent verification link, naming its masked destination when the flow reports one.
    func verificationSentMessage(_ result: UserAttributeVerificationResult) -> String {
        guard let destination = result.maskedDestination, !destination.isEmpty else {
            return resolve("admin.users.details.verification.sent_generic")
        }
        return resolve("admin.users.details.verification.sent", ["destination": destination])
    }
}

/// A translated success message.
struct AdminSuccessNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle")
            .font(.subheadline)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
            .accessibilityElement(children: .combine)
    }
}

/// An attribute row with its verification status and, when `onSend` is set, the action that sends the
/// user a verification link.
struct UserAttributeVerificationRow: View {
    let i18n: ThunderIDI18n
    let name: String
    let value: String
    let isVerified: Bool
    let isSending: Bool
    let isUpdating: Bool
    let onSend: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                statusBadge
                Spacer(minLength: 0)
                if !isVerified, let onSend {
                    sendButton(action: onSend)
                }
            }
        }
        .font(.subheadline)
    }

    private var statusBadge: some View {
        let color = isVerified ? colorScheme.userProfileVerified : colorScheme.userProfileUnverified
        return ProfileStatusLabel(
            label: i18n.resolve(isVerified ? "verifyAttribute.status.verified" : "verifyAttribute.status.unverified"),
            isVerified: isVerified,
            identifier: "admin-user-details-verification-status-\(name)"
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func sendButton(action: @escaping () -> Void) -> some View {
        let verify = i18n.resolve("admin.users.details.verification.verify")
        return Button(action: action) {
            ZStack {
                Label(verify, systemImage: "paperplane")
                    .foregroundStyle(isUpdating ? Color.secondary : Color.accentColor)
                    .opacity(isSending ? 0 : 1)
                if isSending {
                    ProgressView().accessibilityHidden(true)
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.vertical, 5)
        }
        .buttonStyle(.borderless)
        .disabled(isSending || isUpdating)
        .accessibilityLabel("\(verify) \(name)")
        .accessibilityIdentifier("admin-user-details-verification-send-\(name)")
    }
}
