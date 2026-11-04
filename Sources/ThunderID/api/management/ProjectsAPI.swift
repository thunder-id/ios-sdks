// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Project management operations, reached through `ThunderIDClient.projects`. The collection URL comes
/// from `endpoints.projects`, otherwise `{baseUrl}/projects`. Only the Control Plane serves projects.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ProjectsAPI {
    let transport: ManagementTransport

    /// Returns a page of projects, oldest first.
    public func list(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ProjectListResponse {
        try await transport.send("GET", query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a project.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Project {
        try await transport.send("GET", [id], fetcher: fetcher)
    }

    /// Creates a project and returns it.
    public func create(_ project: CreateProjectRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Project {
        try await transport.send("POST", body: project, fetcher: fetcher)
    }

    /// Updates a project's display name and description and returns it.
    public func update(id: String, _ project: UpdateProjectRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Project {
        try await transport.send("PUT", [id], body: project, fetcher: fetcher)
    }

    /// Deletes a project.
    public func delete(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [id], fetcher: fetcher)
    }
}
