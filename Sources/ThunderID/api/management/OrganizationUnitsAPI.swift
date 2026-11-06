// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Organization unit management operations, reached through `ThunderIDClient.organizationUnits`. The
/// collection URL comes from `endpoints.organizationUnits`, otherwise `{baseUrl}/organization-units`.
/// An organization unit is addressed by identifier or by handle path (`engineering/frontend`), whose
/// segments are each encoded with the slashes kept.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct OrganizationUnitsAPI {
    let transport: ManagementTransport

    /// Returns a page of the root organization units.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> OrganizationUnitListResponse {
        try await transport.send(
            "GET",
            query: .page(limit, offset) + .management([("filter", filter)]),
            fetcher: fetcher
        )
    }

    /// Returns an organization unit by identifier.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> OrganizationUnit {
        try await transport.send("GET", try OrganizationUnitReference.id(id).segments(), fetcher: fetcher)
    }

    /// Returns an organization unit by handle path.
    public func get(path: String, fetcher: ThunderIDFetcher? = nil) async throws -> OrganizationUnit {
        try await transport.send("GET", try OrganizationUnitReference.path(path).segments(), fetcher: fetcher)
    }

    /// Creates an organization unit and returns it as the server stored it.
    public func create(_ unit: OrganizationUnitRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> OrganizationUnit {
        try await transport.send("POST", body: unit, fetcher: fetcher)
    }

    /// Updates an organization unit by identifier and returns it.
    public func update(id: String, _ unit: OrganizationUnitRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> OrganizationUnit {
        try await transport.send("PUT", try OrganizationUnitReference.id(id).segments(), body: unit, fetcher: fetcher)
    }

    /// Updates an organization unit by handle path and returns it.
    public func update(path: String, _ unit: OrganizationUnitPathRequest, fetcher: ThunderIDFetcher? = nil)
        async throws -> OrganizationUnit {
        try await transport.send(
            "PUT",
            try OrganizationUnitReference.path(path).segments(),
            body: unit,
            fetcher: fetcher
        )
    }

    /// Deletes an organization unit by identifier.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult(
            "DELETE",
            try OrganizationUnitReference.id(id).segments(),
            fetcher: fetcher
        )
    }

    /// Deletes an organization unit by handle path.
    public func delete(path: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult(
            "DELETE",
            try OrganizationUnitReference.path(path).segments(),
            fetcher: fetcher
        )
    }

    /// Returns a page of the organization units directly beneath one.
    public func children(
        _ unit: OrganizationUnitReference,
        limit: Int? = nil,
        offset: Int? = nil,
        filter: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> OrganizationUnitListResponse {
        try await transport.send(
            "GET",
            try unit.segments() + ["ous"],
            query: .page(limit, offset) + .management([("filter", filter)]),
            fetcher: fetcher
        )
    }

    /// Returns a page of an organization unit's users, each with its resolved `display` value: the
    /// users it owns, then the users shared into it.
    public func users(
        _ unit: OrganizationUnitReference,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> OrganizationUnitUserListResponse {
        try await transport.send(
            "GET",
            try unit.segments() + ["users"],
            query: .page(limit, offset) + .management([("include", "display")]),
            fetcher: fetcher
        )
    }

    /// Returns a page of an organization unit's groups.
    public func groups(
        _ unit: OrganizationUnitReference,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> OrganizationUnitGroupListResponse {
        try await transport.send("GET", try unit.segments() + ["groups"], query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a page of an organization unit's roles.
    public func roles(
        _ unit: OrganizationUnitReference,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> OrganizationUnitRoleListResponse {
        try await transport.send("GET", try unit.segments() + ["roles"], query: .page(limit, offset), fetcher: fetcher)
    }
}
