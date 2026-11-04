// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// The names follow the server's `/gateways/{id}/master` resource, which the other SDKs share.
// swiftlint:disable inclusive_language

/// What a gateway holds, resource by resource, and how each resource got there.
public extension GatewaysAPI {
    /// Returns the gateway's latest master. A gateway nothing was applied to holds the empty master,
    /// `number` 0, with no entries or resources.
    func master(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> GatewayMaster {
        try await transport.send("GET", [id, "master"], fetcher: fetcher)
    }

    /// Returns the gateway's kept masters, newest first, each with its summary but without entries or
    /// resources.
    func masterHistory(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> [GatewayMaster] {
        try await transport.send("GET", [id, "master", "history"], fetcher: fetcher)
    }

    /// Returns one resource's entry in each kept master that records it, newest first.
    /// - Parameters:
    ///   - resourceType: The part of ``GatewayMasterEntry/key`` before the slash.
    ///   - resourceId: The part of ``GatewayMasterEntry/key`` after the slash.
    func masterResource(
        id: String,
        resourceType: String,
        resourceId: String,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> GatewayResourceHistory {
        try await transport.send("GET", [id, "master", "resources", resourceType, resourceId], fetcher: fetcher)
    }
}
// swiftlint:enable inclusive_language
