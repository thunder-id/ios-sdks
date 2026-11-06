// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// The names follow the server's `/gateways/{id}/master` resource, which the other SDKs share.
// swiftlint:disable inclusive_language
/// What a gateway answered when it refused a resource.
public struct GatewayEntryFailure: Codable, Equatable {
    public let code: String?
    public let message: String?
    public let description: String?
}

/// One resource in a gateway's master.
public struct GatewayMasterEntry: Codable {
    /// `<resourceType>/<id>`, as a diff reports it.
    public let key: String?
    public let resourceType: String?
    public let id: String?
    public let name: String?
    /// The SHA-256 of the document as the master holds it.
    public let contentHash: String?
    /// The hash of the version the last apply of this resource sent it from.
    public let sourceVersion: String?
    public let origin: String?
    /// `deployed`, `failed` or `removed`.
    public let state: String?
    /// Set when `state` is `failed`.
    public let failure: GatewayEntryFailure?
    /// When the entry was last written.
    public let at: String? // swiftlint:disable:this identifier_name
    /// The user whose apply last wrote the entry.
    public let by: ConfigurationActor? // swiftlint:disable:this identifier_name
}

/// How many resources a master holds in each state.
public struct GatewayMasterSummary: Codable, Equatable {
    public let deployed: Int?
    public let failed: Int?
    public let removed: Int?
}

/// What one gateway holds, as the gateway last accepted it. A listing leaves out `entries` and `resources`.
public struct GatewayMaster: Codable {
    public let gatewayId: String?
    /// Orders the gateway's masters from 1; 0 is the empty master.
    public let number: Int?
    /// The hash naming the master by what it holds. `nil` for the empty master.
    public let master: String?
    public let createdAt: String?
    public let createdBy: ConfigurationActor?
    /// Every resource the gateway holds, one YAML document each.
    public let resources: String?
    public let summary: GatewayMasterSummary?
    public let entries: [GatewayMasterEntry]?
}

/// A resource's entry in one kept master.
public struct GatewayResourceHistoryItem: Codable {
    /// The hash of the master the entry is from.
    public let master: String?
    public let number: Int?
    public let entry: GatewayMasterEntry?
}

/// A resource's entry in each kept master that records it, newest first.
public struct GatewayResourceHistory: Codable {
    public let gatewayId: String?
    public let key: String?
    public let history: [GatewayResourceHistoryItem]?
}
// swiftlint:enable inclusive_language
