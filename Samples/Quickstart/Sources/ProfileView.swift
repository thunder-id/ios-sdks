// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

// MARK: - Profile Screen

struct ProfileScreen: View {
    @EnvironmentObject private var state: ThunderIDState
    let isDark: Bool
    let bgColor: Color
    let textColor: Color
    let mutedColor: Color
    let borderColor: Color
    let cardColor: Color
    let primaryBlue: Color
    let onBack: () -> Void

    @State private var showEditProfile = false

    /// Same precedence the SDK's `UserAvatar` uses for its seed name.
    private var displayName: String {
        let user = state.user
        let givenName = user?["given_name"] as? String
        let familyName = user?["family_name"] as? String
        let fullName = [givenName, familyName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return user?.displayName ?? user?.username ?? user?.email ?? "Guest"
    }
    private var email: String? { state.user?.email }
    private var userId: String { state.user?.sub ?? "—" }

    private struct Attribute: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// Every remaining claim on the token, rendered as a label/value pair.
    private var attributes: [Attribute] {
        guard let user = state.user else { return [] }
        return user.profileClaims
            .compactMap { key, claim in
                guard let value = Self.format(claim.value) else { return nil }
                return Attribute(label: Self.label(for: key), value: value)
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private static func format(_ value: Any) -> String? {
        switch value {
        case let text as String:
            return text.isEmpty ? nil : text
        case let flag as Bool:
            return flag ? "Yes" : "No"
        case let number as Int:
            return String(number)
        case let number as Double:
            return String(number)
        case let list as [AnyCodable]:
            let items = list.compactMap { format($0.value) }
            return items.isEmpty ? nil : items.joined(separator: ", ")
        default:
            return nil
        }
    }

    /// Humanizes a claim key for display: `given_name` -> "Given Name".
    private static func label(for key: String) -> String {
        let spaced = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
        return spaced
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back nav
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Home")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(primaryBlue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Text("Profile")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                identitySection

                // Account details section
                sectionHeader("ACCOUNT DETAILS")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                detailsCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .background(bgColor)
        .sheet(isPresented: $showEditProfile) {
            NavigationStack {
                ScrollView {
                    UserProfile {
                        showEditProfile = false
                    } onError: {
                    }
                    .padding(24)
                }
                .navigationTitle("Edit Profile")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditProfile = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    private var identitySection: some View {
        VStack(spacing: 12) {
            UserAvatar(size: 56)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textColor)
                if let email {
                    Text(email)
                        .font(.system(size: 14))
                        .foregroundColor(mutedColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(mutedColor)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow(label: "User ID") {
                Text(userId)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(mutedColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ForEach(attributes) { attribute in
                rowDivider
                detailRow(label: attribute.label) {
                    valueText(attribute.value)
                }
            }
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
    }

    private var rowDivider: some View {
        Divider()
            .background(borderColor)
            .padding(.leading, 16)
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(mutedColor)
            .multilineTextAlignment(.trailing)
    }

    private func detailRow<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(textColor)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
