// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Flow listing, reached through `ThunderIDClient.flows`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct FlowsAPI {
    let transport: ManagementTransport

    /// Returns a page of flows, optionally restricted to one flow type.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        flowType: FlowType? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ManagedFlowListResponse {
        try await transport.list(
            query: .management([
                ("flowType", flowType?.rawValue),
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }
}
