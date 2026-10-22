// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

struct SessionView: View {
    enum Tab: String, Hashable {
        case tokens
        case claims
        case permissions
        case events
    }

    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var checks: ChecksModel
    @EnvironmentObject private var log: EventLog
    /// `-sessionTab permissions` as a launch argument opens that inner tab, for screenshots.
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "sessionTab") ?? "") ?? .tokens
    @State private var snapshot = SessionSnapshot.empty
    @State private var revealed: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Session")
                    .font(.system(size: 26))
                    .tracking(-0.5)
                Spacer()
                StatusPill(isSignedIn: state.isSignedIn)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 14) {
                    UserCard(snapshot: snapshot, refresh: refreshToken, signOut: signOut, signIn: signIn)
                    SegmentedPicker(
                        options: [
                            (Tab.tokens, "Tokens"),
                            (Tab.claims, "Claims"),
                            (Tab.permissions, "Permissions"),
                            (Tab.events, "Events")
                        ],
                        selection: $tab
                    )
                    tabContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .task(id: state.user?.sub) { await reload() }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .tokens:
            TokensList(tokens: snapshot.tokens, revealed: $revealed, storageService: checks.storage.service)
        case .claims:
            ClaimsList(claims: snapshot.claims, source: snapshot.claimsSource)
        case .permissions:
            PermissionsPanel()
        case .events:
            EventList(entries: Array(log.entries.prefix(30)))
        }
    }

    private func reload() async {
        snapshot = await SessionSnapshot.load(client: state.client, storage: checks.storage)
    }

    private func refreshToken() {
        Task {
            await run(.tokenRefresh)
            await reload()
        }
    }

    private func signOut() {
        Task {
            await run(.signOut)
            tab = .events
            await reload()
        }
    }

    private func signIn(_ id: CapabilityID) {
        Task {
            await run(id)
            await reload()
        }
    }

    private func run(_ id: CapabilityID) async {
        guard let capability = CapabilityCatalog.all.first(where: { $0.id == id }) else { return }
        await checks.run(capability)
    }
}

private struct StatusPill: View {
    let isSignedIn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .frame(width: 6, height: 6)
            Text(isSignedIn ? "Signed in" : "Signed out")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(isSignedIn ? Palette.successText : Palette.text(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((isSignedIn ? Palette.success : Palette.idle).opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct UserCard: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var checks: ChecksModel
    let snapshot: SessionSnapshot
    let refresh: () -> Void
    let signOut: () -> Void
    let signIn: (CapabilityID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BaseUserAvatar(user: state.user, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 16))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(Palette.text(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if state.isSignedIn {
                ExpiryBar(issuedAt: snapshot.issuedAt, expiresAt: snapshot.expiresAt)
                HStack(spacing: 8) {
                    CardButton(label: "Refresh token", style: .neutral, action: refresh)
                    CardButton(label: "Sign out", style: .danger, action: signOut)
                }
            } else {
                HStack(spacing: 8) {
                    CardButton(label: "System browser", style: .primary) { signIn(.browserSignIn) }
                    CardButton(label: "App-native", style: .neutral) { signIn(.nativeSignIn) }
                }
            }
        }
        .playgroundCard()
    }

    private var displayName: String {
        guard let user = state.user else { return "Not signed in" }
        if let given = user["given_name"] as? String, let family = user["family_name"] as? String {
            return "\(given) \(family)"
        }
        return user.displayName ?? user.username ?? user.email ?? user.sub ?? "Signed in"
    }

    private var subtitle: String {
        guard let user = state.user else { return "Sign in to inspect tokens and claims" }
        return [user.email, user.sub.map { "sub \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ExpiryBar: View {
    let issuedAt: Date?
    let expiresAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expiresAt?.timeIntervalSince(context.date) ?? 0))
            VStack(spacing: 7) {
                HStack {
                    Text("Access token")
                    Spacer()
                    Text(label(remaining))
                        .font(.mono(12.5))
                }
                .font(.system(size: 12.5))
                .foregroundColor(Palette.text(0.6))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.text(0.08))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Palette.primary, Palette.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: proxy.size.width * fraction(remaining))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private func label(_ remaining: Int) -> String {
        guard expiresAt != nil else { return "no expiry" }
        guard remaining > 0 else { return "expired" }
        return String(format: "expires in %02d:%02d", remaining / 60, remaining % 60)
    }

    private func fraction(_ remaining: Int) -> CGFloat {
        guard let expiresAt else { return 0 }
        let lifetime = issuedAt.map { expiresAt.timeIntervalSince($0) } ?? 3600
        return CGFloat(min(1, Double(remaining) / max(lifetime, 1)))
    }
}

private struct CardButton: View {
    enum Style {
        case primary
        case neutral
        case danger
    }

    let label: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(style == .danger ? Color(hex: 0xF87171) : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary: Palette.primaryGradient
        case .neutral: Palette.text(0.06)
        case .danger: Color.clear
        }
    }

    private var border: Color {
        switch style {
        case .primary: return .clear
        case .neutral: return Palette.text(0.1)
        case .danger: return Palette.danger.opacity(0.45)
        }
    }
}
