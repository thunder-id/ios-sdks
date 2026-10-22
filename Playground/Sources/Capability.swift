// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum CapabilityID: String, CaseIterable {
    case browserSignIn
    case nativeSignIn
    case passkey
    case biometric
    case signOut
    case redirectCallback
    case tokenRefresh
    case secureStorage
    case userInfo
    case organizations
    case theming
    case translations
    case managementEndpoints
    case groups
    case groupMembers
    case roles
    case roleAssignments
    case userGroups
    case agentTypes
    case agentMemberships
    case adminWrites
    case permissionHierarchy
    case grantedPermissions
}

enum CheckStatus: Equatable {
    case idle(String?)
    case running
    case pass(String)
    case fail(String)
    case unavailable(String)

    var isPass: Bool {
        if case .pass = self { return true }
        return false
    }

    var isRunning: Bool { self == .running }

    var note: String? {
        switch self {
        case .idle(let note): return note
        case .running: return nil
        case .pass(let note), .fail(let note), .unavailable(let note): return note
        }
    }
}

struct Capability: Identifiable {
    enum Mode: Equatable {
        /// Runs without user input, so Run all includes it.
        case automatic
        /// Needs the user (a browser sheet, a sign-in form, or ending the session), so it only runs on tap.
        case interactive
        /// The iOS SDK has no API for it.
        case unavailable(String)
    }

    let id: CapabilityID
    let name: String
    let api: String
    let mode: Mode

    var isAvailable: Bool {
        if case .unavailable = mode { return false }
        return true
    }
}

struct CapabilitySection: Identifiable {
    let name: String
    let items: [Capability]

    var id: String { name }
}

enum CapabilityCatalog {
    static let sections: [CapabilitySection] = [
        CapabilitySection(name: "Authentication", items: [
            Capability(
                id: .browserSignIn,
                name: "Sign in (system browser)",
                api: "buildSignInURL() · ASWebAuthenticationSession",
                mode: .interactive
            ),
            Capability(
                id: .nativeSignIn,
                name: "Sign in (app-native flow)",
                api: "SignIn(applicationId:) · signIn(payload:request:)",
                mode: .interactive
            ),
            Capability(
                id: .passkey,
                name: "Passkey sign-in",
                api: "PasskeyAuthSession · ASAuthorizationController",
                mode: .automatic
            ),
            Capability(
                id: .biometric,
                name: "Biometric unlock",
                api: "LocalAuthentication · Face ID",
                mode: .unavailable(
                    "The iOS SDK has no biometric API. Gate the app with LocalAuthentication yourself."
                )
            ),
            Capability(id: .signOut, name: "Sign out", api: "signOut()", mode: .interactive),
            Capability(
                id: .redirectCallback,
                name: "Redirect callback",
                api: "handleRedirectCallback(url:) · CFBundleURLTypes",
                mode: .automatic
            )
        ]),
        CapabilitySection(name: "Session", items: [
            Capability(
                id: .tokenRefresh,
                name: "Token refresh",
                api: "getAccessToken() · auto refresh",
                mode: .automatic
            ),
            Capability(
                id: .secureStorage,
                name: "Secure token storage",
                api: "KeychainStorageAdapter",
                mode: .automatic
            ),
            Capability(id: .userInfo, name: "User info", api: "getUser()", mode: .automatic),
            Capability(
                id: .organizations,
                name: "Organizations",
                api: "organizations()",
                mode: .unavailable(
                    "The iOS SDK has no organizations API yet; only the organizationHandle config key."
                )
            )
        ]),
        CapabilitySection(name: "UI", items: [
            Capability(
                id: .theming,
                name: "Theming and dark mode",
                api: "ThunderIDTheme",
                mode: .unavailable(
                    "No theming API. Components use system colors and follow the color scheme; "
                        + "preview both in Components."
                )
            ),
            Capability(
                id: .translations,
                name: "Translations",
                api: "ThunderIDI18n · setLocale(_:)",
                mode: .automatic
            )
        ]),
        managementSection,
        accessSection
    ]

    static var all: [Capability] { sections.flatMap(\.items) }
}

extension CapabilityCatalog {
    /// The management API.
    private static let managementSection = CapabilitySection(name: "Management", items: [
        Capability(
            id: .managementEndpoints,
            name: "Management endpoints",
            api: "ThunderIDConfig.endpoints · ThunderIDEndpoints",
            mode: .automatic
        ),
        Capability(id: .groups, name: "Groups", api: "groups.list() · groups.get(id:)", mode: .automatic),
        Capability(id: .groupMembers, name: "Group members", api: "groups.members(id:)", mode: .automatic),
        Capability(id: .roles, name: "Roles", api: "roles.list() · roles.get(id:)", mode: .automatic),
        Capability(
            id: .roleAssignments,
            name: "Role assignments",
            api: "roles.assignments(id:type:)",
            mode: .automatic
        ),
        Capability(
            id: .userGroups,
            name: "User groups and types",
            api: "users.groups(id:) · users.types()",
            mode: .automatic
        ),
        Capability(id: .agentTypes, name: "Agent types", api: "agents.types()", mode: .automatic),
        Capability(
            id: .agentMemberships,
            name: "Agent groups and roles",
            api: "agents.groups(id:) · agents.roles(id:)",
            mode: .automatic
        ),
        Capability(
            id: .adminWrites,
            name: "Group and role writes",
            api: "groups.create · addMembers · roles.create · addAssignments · delete",
            mode: .interactive
        )
    ])

    private static let accessSection = CapabilitySection(name: "Permissions", items: [
        Capability(
            id: .permissionHierarchy,
            name: "Permission hierarchy",
            api: "ThunderIDPermissions.has(_:_:) · fromAccessToken(_:)",
            mode: .automatic
        ),
        Capability(
            id: .grantedPermissions,
            name: "Granted permissions",
            api: "getGrantedPermissions() · GrantedPermissions",
            mode: .automatic
        )
    ])
}

/// Identifiers the management checks found on the server, so later checks and the component
/// explorer's live stories have a real group, role, user and agent to point at.
@MainActor
final class ManagementIds: ObservableObject {
    @Published var groupId: String?
    @Published var roleId: String?
    @Published var userId: String?
    @Published var agentId: String?
}
