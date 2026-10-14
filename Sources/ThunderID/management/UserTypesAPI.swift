// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User type listing, reached through `ThunderIDClient.userTypes`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct UserTypesAPI {
    let transport: ManagementTransport

    /// Returns a page of user types.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ManagedUserTypeListResponse {
        try await transport.list(
            query: .management([
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init))
            ]),
            fetcher: fetcher
        )
    }
}
