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

    private var displayName: String { state.user?.displayName ?? state.user?.username ?? "Guest" }
    private var email: String? { state.user?.email }
    private var userId: String { state.user?.sub ?? "—" }
    private var username: String? { state.user?.username }

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
            if let username {
                Divider()
                    .background(borderColor)
                    .padding(.leading, 16)
                detailRow(label: "Username") {
                    Text(username)
                        .font(.system(size: 13))
                        .foregroundColor(mutedColor)
                }
            }
        }
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: 1))
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
