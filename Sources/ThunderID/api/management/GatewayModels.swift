// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A registered gateway: a runtime that applies configuration versions from this plane.
public struct Gateway: Codable {
    public let id: String?
    public let name: String?
    public let baseUrl: String?
    public let caCertificate: String?
    public let isDefault: Bool?
    public let createdAt: String?
    public let updatedAt: String?
}

/// A newly registered gateway with its key. This is the only time the key can be read.
public struct GatewayRegistration: Codable {
    public let gateway: Gateway
    /// The key the gateway presents. `nil` when the caller supplied it.
    public let key: String?

    private enum CodingKeys: String, CodingKey {
        case key
    }

    public init(from decoder: Decoder) throws {
        gateway = try Gateway(from: decoder)
        key = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .key)
    }

    public func encode(to encoder: Encoder) throws {
        try gateway.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(key, forKey: .key)
    }
}

/// The payload used to register a gateway.
public struct RegisterGatewayRequest: Codable {
    public var name: String
    public var baseUrl: String
    /// The key the gateway presents. The server generates one when it is `nil`.
    public var key: String?
    public var caCertificate: String?
    public var isDefault: Bool?

    public init(
        name: String,
        baseUrl: String,
        key: String? = nil,
        caCertificate: String? = nil,
        isDefault: Bool? = nil
    ) {
        self.name = name
        self.baseUrl = baseUrl
        self.key = key
        self.caCertificate = caCertificate
        self.isDefault = isDefault
    }
}

/// The payload used to update a gateway. Only the fields set change.
public struct UpdateGatewayRequest: Codable {
    public var name: String?
    public var baseUrl: String?
    public var caCertificate: String?
    public var key: String?

    public init(name: String? = nil, baseUrl: String? = nil, caCertificate: String? = nil, key: String? = nil) {
        self.name = name
        self.baseUrl = baseUrl
        self.caCertificate = caCertificate
        self.key = key
    }
}

/// Someone who made a change.
public struct ConfigurationActor: Codable, Equatable {
    public let id: String
    public let name: String
}

/// A place a resource references a variable or a secret.
public struct ValueReference: Codable, Equatable {
    public let name: String?
    /// `variable` or `secret`.
    public let kind: String?
    public let resourceType: String?
    public let resourceId: String?
    public let resourceName: String?
    public let field: String?
    public let list: Bool?
}

/// One line of a change.
public struct ConfigurationDiffLine: Codable, Equatable {
    /// ` `, `+` or `-`.
    public let kind: String?
    public let text: String?
}

/// One resource's change between two configuration versions.
public struct ConfigurationChange: Codable {
    public let key: String?
    public let excluded: Bool?
    public let skipped: Bool?
    public let resourceType: String?
    public let id: String?
    public let name: String?
    /// `added`, `updated`, `deleted` or `unchanged`.
    public let change: String?
    public let lines: [ConfigurationDiffLine]?
}

/// How many resources each kind of change touched.
public struct ConfigurationDiffSummary: Codable, Equatable {
    public let added: Int?
    public let updated: Int?
    public let deleted: Int?
    public let unchanged: Int?
}

/// The difference between a gateway's applied configuration and another version.
public struct GatewayConfigurationDiff: Codable {
    public let fromVersion: String?
    public let toVersion: String?
    public let summary: ConfigurationDiffSummary?
    public let changes: [ConfigurationChange]?
    public let misplacedSecrets: [ValueReference]?
}

/// The variables, secrets and references an apply found missing or changed.
public struct GatewayValueChanges: Codable {
    public let variables: [String]?
    public let secrets: [String]?
    public let references: [ValueReference]?
}

/// What applying or reverting a gateway's configuration did, or would do on a dry run.
public struct GatewayApplyResult: Codable {
    public let gatewayId: String?
    public let dryRun: Bool?
    public let diff: GatewayConfigurationDiff?
    /// The import result the gateway reported.
    public let `import`: [String: AnyCodable]?
    public let recorded: Bool?
    public let missing: GatewayValueChanges?
    public let changed: GatewayValueChanges?
    /// Whether the apply was queued for when the gateway is reachable.
    public let queued: Bool?
    public let queuedVersion: String?
}

/// The payload used to apply a configuration version to a gateway.
public struct ApplyGatewayConfigurationRequest: Codable, Equatable {
    /// The version to apply; the current one when `nil`.
    public var version: String?
    public var dryRun: Bool?
    /// Whether to remove resources the version no longer has.
    public var confirmRemovals: Bool?
    /// Only these change keys.
    public var selection: [String]?
    /// Not these change keys.
    public var skip: [String]?

    public init(
        version: String? = nil,
        dryRun: Bool? = nil,
        confirmRemovals: Bool? = nil,
        selection: [String]? = nil,
        skip: [String]? = nil
    ) {
        self.version = version
        self.dryRun = dryRun
        self.confirmRemovals = confirmRemovals
        self.selection = selection
        self.skip = skip
    }
}

/// The payload used to revert a gateway to the configuration it had before the last apply.
public struct RevertGatewayConfigurationRequest: Codable, Equatable {
    public var confirmRemovals: Bool?
    public var dryRun: Bool?

    public init(confirmRemovals: Bool? = nil, dryRun: Bool? = nil) {
        self.confirmRemovals = confirmRemovals
        self.dryRun = dryRun
    }
}

/// The configuration version a gateway runs.
public struct GatewayAppliedVersion: Codable {
    public let gatewayId: String?
    public let appliedVersion: String?
    public let previousVersion: String?
    public let appliedAt: String?
    public let appliedBy: ConfigurationActor?
}

/// One resource a gateway runs.
public struct GatewayAppliedResource: Codable {
    public let resourceType: String
    public let id: String
    public let resource: [String: AnyCodable]
    public let parts: [String: AnyCodable]?
}

/// A resource an apply left out, and why.
public struct GatewaySkippedResource: Codable {
    public let resourceType: String
    public let id: String?
    public let code: String
    public let reason: String
}

/// The configuration a gateway runs.
public struct GatewayAppliedConfiguration: Codable {
    public let gatewayId: String
    public let version: String?
    public let appliedAt: String?
    public let resources: [GatewayAppliedResource]
    public let skipped: [GatewaySkippedResource]?
}
