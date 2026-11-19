// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The grant types a personal agent can use, in the order an edit form offers them.
public enum PersonalAgentGrantTypes {
    public static let authorizationCode = "authorization_code"
    public static let ciba = "urn:openid:params:grant-type:ciba"
    public static let refreshToken = "refresh_token"

    /// Every grant type a personal agent can use.
    public static let all: [String] = [authorizationCode, ciba, refreshToken]

    /// The translation key that labels each of ``all``.
    public static let labelKeys: [String: String] = [
        authorizationCode: "user.agents.grant_types.authorization_code",
        ciba: "user.agents.grant_types.ciba",
        refreshToken: "user.agents.grant_types.refresh_token"
    ]
}

/// The suspension action an agent's owner can take on it: ``unsuspend`` while the owner holds it suspended,
/// otherwise ``suspend``. The owner's suspension is independent of any other party's, so an agent the
/// organization suspended, or one suspended while its owner's account is, can still take the owner's own
/// suspension, and lifting the owner's leaves the others in force.
public enum MeAgentSuspensionAction: String, CaseIterable {
    case suspend
    case unsuspend

    /// The action to offer for an agent with this status, from a read of the owner's agent.
    public static func available(for status: AccessStatus?) -> MeAgentSuspensionAction {
        status?.suspendedBy.contains(.owner) == true ? .unsuspend : .suspend
    }
}

public extension Agent {
    /// Whether this is a personal agent: one that acts only for its owner, a user.
    var isPersonal: Bool { kind == .personal }

    /// The agent's OAuth settings, when it has an OAuth client.
    var oauthConfig: OAuth2Config? {
        inboundAuthConfig?.first { $0.type == "oauth2" }?.config
    }
}

public extension BasicAgent {
    /// Whether this is a personal agent: one that acts only for its owner, a user.
    var isPersonal: Bool { kind == .personal }
}

/// The values of a personal agent's edit form, starting from what the server holds.
public struct PersonalAgentFormValues: Equatable {
    public var name: String
    public var description: String
    /// The agent's text attributes other than `name`, keyed by attribute name. Attributes that hold another
    /// kind of value are not edited, and are sent back unchanged.
    public var attributes: [String: String]
    public var grantTypes: [String]
    /// The text of the redirect URI field: URIs separated by whitespace, one per line by default.
    public var redirectUris: String

    public init(agent: Agent) {
        let oauth = agent.oauthConfig
        name = agent.attributes?["name"]?.value as? String ?? ""
        description = agent.description ?? ""
        attributes = (agent.attributes ?? [:]).reduce(into: [:]) { result, entry in
            if entry.key != "name", let text = entry.value.value as? String {
                result[entry.key] = text
            }
        }
        grantTypes = oauth?.grantTypes ?? []
        redirectUris = (oauth?.redirectUris ?? []).joined(separator: "\n")
    }

    /// The redirect URIs the field holds.
    public var redirectUriList: [String] {
        redirectUris
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    /// Whether the values can be saved: a name is required, and the authorization code grant needs a
    /// redirect URI.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!grantTypes.contains(PersonalAgentGrantTypes.authorizationCode) || !redirectUriList.isEmpty)
    }

    /// The update request for `agent`. Attributes the form does not edit are sent back unchanged, since an
    /// update replaces them all.
    public func updateRequest(for agent: Agent) -> UpdateMeAgentRequest {
        var merged = agent.attributes ?? [:]
        for (key, value) in attributes {
            merged[key] = AnyCodable(value)
        }
        merged["name"] = AnyCodable(name.trimmingCharacters(in: .whitespacesAndNewlines))
        return UpdateMeAgentRequest(
            attributes: merged,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            grantTypes: grantTypes,
            redirectUris: redirectUriList
        )
    }
}
