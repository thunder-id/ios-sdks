// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where the reported actions apply: `deployment` (every organization unit) or `ou` (only ``ouId``).
/// A type this SDK does not know keeps its raw value.
public struct CapabilityScope: Codable, Equatable {
    public let type: String
    /// The organization unit the actions apply to, when ``type`` is `ou`.
    public let ouId: String?

    public init(type: String, ouId: String? = nil) {
        self.type = type
        self.ouId = ouId
    }
}

/// The management actions the signed-in user's access token allows, as the server reports them from
/// `GET /capabilities`.
///
/// Capabilities decide what an application offers, never what is allowed: the server authorizes every
/// management request, including the organization unit of the record it acts on. The SDK never skips or
/// blocks a request because of them.
public struct Capabilities: Codable, Equatable {
    public let scope: CapabilityScope
    /// Each resource (`app`, `user`, `group`, ...) mapped to each of its actions (`view`, `create`,
    /// `update`, `delete`) and whether the user may perform it.
    public let resources: [String: [String: Bool]]

    public init(scope: CapabilityScope, resources: [String: [String: Bool]]) {
        self.scope = scope
        self.resources = resources
    }

    /// Whether the user may perform `action` on `resource`. False for anything the server did not report.
    public func can(_ resource: String, _ action: String = "view") -> Bool {
        resources[resource]?[action] == true
    }
}

/// What the signed-in user may do with one management record.
///
/// A record locked by the server (`isReadOnly`) or shared into the user's organization unit by another
/// one (`isOwnedByOU == false`) is read-only. Like ``Capabilities``, it decides what to offer, not what
/// the server allows.
public struct RecordAccess: Equatable {
    /// The record cannot be edited: it is locked, shared in, or the user may not `update` its resource.
    public let readOnly: Bool
    /// The record can be deleted: it is neither locked nor shared in, and the user may `delete`.
    public let canDelete: Bool
    /// The record's runtime state (active, suspended) can change: it is not shared in and the user may
    /// `update`, whatever `isReadOnly` says.
    public let canChangeState: Bool

    /// - Parameters:
    ///   - resource: The capability resource the record belongs to, such as `app` or `user`.
    ///   - isReadOnly: The record's `isReadOnly`, or `nil` when it has none.
    ///   - isOwnedByOU: The record's `isOwnedByOU`, or `nil` when it has none.
    ///   - can: Answers whether the user may perform an action on a resource.
    public init(
        resource: String,
        isReadOnly: Bool? = nil,
        isOwnedByOU: Bool? = nil,
        can: (_ resource: String, _ action: String) -> Bool
    ) {
        let sharedIn = isOwnedByOU == false
        let locked = isReadOnly == true || sharedIn
        readOnly = locked || !can(resource, "update")
        canDelete = !locked && can(resource, "delete")
        canChangeState = !sharedIn && can(resource, "update")
    }
}

public extension ThunderIDClient {
    /// Reads the management actions the signed-in user's access token allows. The URL comes from
    /// `endpoints.capabilities`, otherwise `{baseUrl}/capabilities`, and `fetcher` takes precedence over
    /// `ThunderIDConfig.http.fetcher`.
    ///
    /// The answer decides what to offer, not what is allowed: the server still authorizes every request.
    func getCapabilities(fetcher: ThunderIDFetcher? = nil) async throws -> Capabilities {
        try await managementTransport("capabilities", override: \.capabilities).send("GET", fetcher: fetcher)
    }
}
