// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// The permissions the access token grants, read by the SDK's `GrantedPermissions`, and whether
/// they cover the management permissions the admin components need.
struct PermissionsPanel: View {
    @EnvironmentObject private var state: ThunderIDState

    var body: some View {
        // Wait for initialize(): getAccessToken() force-unwraps the SDK's token refresher, which
        // initialize() assigns after the config, so calling it any earlier crashes.
        if state.isInitialized {
            PermissionsContent(granted: state.grantedPermissions())
                .id(state.user?.sub ?? "signed-out")
        } else {
            EmptyState(text: "Waiting for the SDK to initialize…")
        }
    }
}

private struct PermissionsContent: View {
    /// Management permissions to probe. A parent such as `system` covers all of them.
    private static let probes = [
        "system:user:view", "system:group:view", "system:group:manage",
        "system:role:view", "system:role:manage", "system:agent:view"
    ]

    @StateObject private var granted: GrantedPermissions
    @State private var custom = ""

    init(granted: @autoclosure @escaping () -> GrantedPermissions) {
        _granted = StateObject(wrappedValue: granted())
    }

    var body: some View {
        VStack(spacing: 8) {
            if granted.permissions.isEmpty {
                EmptyState(text: granted.isLoading ? "Reading the access token…" : "No permissions in the token.")
            } else {
                SectionLabel(text: "Granted · \(granted.permissions.count)")
                VStack(spacing: 0) {
                    ForEach(granted.permissions, id: \.self) { permission in
                        row(permission, detail: nil)
                    }
                }
                .playgroundGroup()
            }
            SectionLabel(text: "ThunderIDPermissions.has")
            VStack(spacing: 0) {
                ForEach(Self.probes, id: \.self) { probe in
                    row(probe, detail: granted.can(probe))
                }
                customProbe
            }
            .playgroundGroup()
            Text("Read from the token's scope or scopes claim by getGrantedPermissions(). The signature is not "
                + "checked, so use it to decide what to show; the server still authorizes every request.")
                .font(.system(size: 12))
                .foregroundColor(Palette.text(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await granted.refresh() }
    }

    private var customProbe: some View {
        HStack(spacing: 10) {
            TextField("Test a permission, e.g. system:user", text: $custom)
                .font(.mono(12.5))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !custom.isEmpty {
                verdict(granted.can(custom))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func row(_ permission: String, detail: Bool?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(permission)
                    .font(.mono(12.5, weight: .medium))
                    .foregroundColor(Palette.accent)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let detail { verdict(detail) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            Divider().overlay(Palette.text(0.06))
        }
    }

    private func verdict(_ allowed: Bool) -> some View {
        Text(allowed ? "granted" : "missing")
            .font(.mono(11.5, weight: .medium))
            .foregroundColor(allowed ? Palette.successText : Palette.text(0.45))
    }
}
