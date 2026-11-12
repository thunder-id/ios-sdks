// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An organization unit directly beneath a sharing policy's issuer, and how far the share reaches.
public struct SharingChildUnit: Codable, Equatable {
    public var ouId: String
    /// `unit` (only that organization unit) or `subtree` (it and everything beneath it).
    public var reach: String

    public init(ouId: String, reach: String) {
        self.ouId = ouId
        self.reach = reach
    }
}

/// The root organization unit of another tree.
public struct SharingRootUnit: Codable, Equatable {
    public var ouId: String

    public init(ouId: String) {
        self.ouId = ouId
    }
}

/// The organization units beneath the issuer a policy reaches. In `all` mode everything beneath it,
/// less `excludedOuIds`; in `selected` mode only `units`.
public struct SharingChildUnits: Codable, Equatable {
    /// `all` or `selected`.
    public var mode: String
    public var excludedOuIds: [String]?
    public var units: [SharingChildUnit]?

    public init(mode: String, excludedOuIds: [String]? = nil, units: [SharingChildUnit]? = nil) {
        self.mode = mode
        self.excludedOuIds = excludedOuIds
        self.units = units
    }

    /// Everything beneath the issuer, less `excluding`.
    public static func all(excluding: [String]? = nil) -> SharingChildUnits {
        SharingChildUnits(mode: "all", excludedOuIds: excluding)
    }

    /// Only the named organization units.
    public static func selected(_ units: [SharingChildUnit]) -> SharingChildUnits {
        SharingChildUnits(mode: "selected", units: units)
    }
}

/// The roots of other trees a policy reaches. In `all` mode every other root, less `excludedOuIds`
/// (only a resource file or an imported document may introduce it); in `selected` mode only `units`.
public struct SharingOtherTreeRoots: Codable, Equatable {
    /// `all` or `selected`.
    public var mode: String
    public var excludedOuIds: [String]?
    public var units: [SharingRootUnit]?

    public init(mode: String, excludedOuIds: [String]? = nil, units: [SharingRootUnit]? = nil) {
        self.mode = mode
        self.excludedOuIds = excludedOuIds
        self.units = units
    }

    /// Only the named roots.
    public static func selected(_ units: [SharingRootUnit]) -> SharingOtherTreeRoots {
        SharingOtherTreeRoots(mode: "selected", units: units)
    }
}

/// Every organization unit, less `excludedOuIds`.
public struct SharingAllUnits: Codable, Equatable {
    public var excludedOuIds: [String]?

    public init(excludedOuIds: [String]? = nil) {
        self.excludedOuIds = excludedOuIds
    }
}

/// The body of a new sharing policy on a user, an application, a role or a flow.
public struct SharingPolicyRequest: Codable, Equatable {
    public var initiatingOuId: String?
    public var childUnits: SharingChildUnits?
    public var otherTreeRoots: SharingOtherTreeRoots?
    public var version: Int?

    public init(
        initiatingOuId: String? = nil,
        childUnits: SharingChildUnits? = nil,
        otherTreeRoots: SharingOtherTreeRoots? = nil,
        version: Int? = nil
    ) {
        self.initiatingOuId = initiatingOuId
        self.childUnits = childUnits
        self.otherTreeRoots = otherTreeRoots
        self.version = version
    }
}

/// The body of a sharing policy update. `version` is the version read, so a concurrent edit is refused.
public struct SharingPolicyUpdateRequest: Codable, Equatable {
    public var allUnits: SharingAllUnits?
    public var childUnits: SharingChildUnits?
    public var otherTreeRoots: SharingOtherTreeRoots?
    public var version: Int

    public init(
        version: Int,
        allUnits: SharingAllUnits? = nil,
        childUnits: SharingChildUnits? = nil,
        otherTreeRoots: SharingOtherTreeRoots? = nil
    ) {
        self.version = version
        self.allUnits = allUnits
        self.childUnits = childUnits
        self.otherTreeRoots = otherTreeRoots
    }
}

/// A recorded sharing policy. Its sections come back in the shape a request states them in.
public struct SharingPolicy: Codable, Equatable {
    public let id: String?
    public let initiatingOuId: String?
    /// `share` or `reshare`.
    public let stage: String?
    public let parentPolicyId: String?
    public let isReadOnly: Bool?
    public let version: Int?
    public let allUnits: SharingAllUnits?
    public let childUnits: SharingChildUnits?
    public let otherTreeRoots: SharingOtherTreeRoots?
}

/// A page of sharing policies.
public struct SharingPolicyListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let policies: [SharingPolicy]
    public let links: [ApiPaginationLink]?
}

/// How one attribute of a shared resource may be overlaid in an organization unit.
public struct OverlayRule: Codable, Equatable {
    public let editable: Bool?
    public let value: [String]?
    public let allowedValues: [String]?
    public let excludedValues: [String]?
}

/// What a shared user, application, role or flow looks like from one organization unit: whether it is
/// visible there, through which policies, and the overlay rule for each attribute.
public struct ResolvedOverlay: Codable, Equatable {
    public let ouId: String?
    /// Whether the organization unit owns the resource rather than being shared it. The server names
    /// this `isOwnedByOU` for every resource, flows included.
    public let isOwnedByOU: Bool?
    public let visible: Bool?
    public let policyIds: [String]?
    public let rules: [String: OverlayRule]?
}

extension ResolvedOverlay {
    private enum CodingKeys: String, CodingKey {
        case ouId, isOwnedByOU, visible, policyIds, rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ouId = try container.decodeIfPresent(String.self, forKey: .ouId)
        isOwnedByOU = try container.decodeIfPresent(Bool.self, forKey: .isOwnedByOU)
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible)
        policyIds = try container.decodeIfPresent([String].self, forKey: .policyIds)
        rules = try container.decodeIfPresent([String: OverlayRule].self, forKey: .rules)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ouId, forKey: .ouId)
        try container.encodeIfPresent(isOwnedByOU, forKey: .isOwnedByOU)
        try container.encodeIfPresent(visible, forKey: .visible)
        try container.encodeIfPresent(policyIds, forKey: .policyIds)
        try container.encodeIfPresent(rules, forKey: .rules)
    }
}

extension ManagementTransport {
    /// The sharing policy operations, shared by users, applications, roles and flows:
    /// `{collection}/{id}/sharing-policies`.
    func sharingPolicies(
        _ id: String,
        limit: Int?,
        offset: Int?,
        fetcher: ThunderIDFetcher?
    ) async throws -> SharingPolicyListResponse {
        try await send("GET", [id, "sharing-policies"], query: .page(limit, offset), fetcher: fetcher)
    }

    func sharingPolicy(_ id: String, policyId: String, fetcher: ThunderIDFetcher?) async throws -> SharingPolicy {
        try await send("GET", [id, "sharing-policies", policyId], fetcher: fetcher)
    }

    func createSharingPolicy(
        _ id: String,
        _ policy: SharingPolicyRequest,
        fetcher: ThunderIDFetcher?
    ) async throws -> SharingPolicy {
        try await send("POST", [id, "sharing-policies"], body: policy, fetcher: fetcher)
    }

    func updateSharingPolicy(
        _ id: String,
        policyId: String,
        _ policy: SharingPolicyUpdateRequest,
        fetcher: ThunderIDFetcher?
    ) async throws -> SharingPolicy {
        try await send("PUT", [id, "sharing-policies", policyId], body: policy, fetcher: fetcher)
    }

    func deleteSharingPolicy(_ id: String, policyId: String, fetcher: ThunderIDFetcher?) async throws {
        try await sendWithoutResult("DELETE", [id, "sharing-policies", policyId], fetcher: fetcher)
    }

    func overlayRules(_ id: String, ouId: String, fetcher: ThunderIDFetcher?) async throws -> ResolvedOverlay {
        try await send("GET", [id, "overlay-rules"], query: .management([("ouId", ouId)]), fetcher: fetcher)
    }
}
