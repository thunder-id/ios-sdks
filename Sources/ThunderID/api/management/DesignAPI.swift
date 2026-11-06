// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Theme and layout management operations, reached through `ThunderIDClient.design`. The collection URL
/// comes from `endpoints.design`, otherwise `{baseUrl}/design`; themes are under `themes` and layouts
/// under `layouts`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct DesignAPI {
    let transport: ManagementTransport

    // MARK: - Themes

    /// Returns a page of themes.
    public func themes(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> ThemeListResponse {
        try await transport.send("GET", ["themes"], query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a theme.
    public func theme(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Theme {
        try await transport.send("GET", ["themes", id], fetcher: fetcher)
    }

    /// Creates a theme and returns it.
    public func createTheme(_ theme: ThemeRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Theme {
        try await transport.send("POST", ["themes"], body: theme, fetcher: fetcher)
    }

    /// Updates a theme and returns it.
    public func updateTheme(id: String, _ theme: ThemeRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Theme {
        try await transport.send("PUT", ["themes", id], body: theme, fetcher: fetcher)
    }

    /// Deletes a theme.
    public func deleteTheme(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", ["themes", id], fetcher: fetcher)
    }

    /// Lists the applications and agents that use a theme.
    public func themeUsages(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ResourceUsagesResponse {
        try await transport.send("GET", ["themes", id, "usages"], query: .page(limit, offset), fetcher: fetcher)
    }

    // MARK: - Layouts

    /// Returns a page of layouts.
    public func layouts(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil) async throws
        -> LayoutListResponse {
        try await transport.send("GET", ["layouts"], query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a layout.
    public func layout(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Layout {
        try await transport.send("GET", ["layouts", id], fetcher: fetcher)
    }

    /// Creates a layout and returns it.
    public func createLayout(_ layout: LayoutRequest, fetcher: ThunderIDFetcher? = nil) async throws -> Layout {
        try await transport.send("POST", ["layouts"], body: layout, fetcher: fetcher)
    }

    /// Updates a layout and returns it.
    public func updateLayout(id: String, _ layout: LayoutRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Layout {
        try await transport.send("PUT", ["layouts", id], body: layout, fetcher: fetcher)
    }

    /// Deletes a layout.
    public func deleteLayout(id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", ["layouts", id], fetcher: fetcher)
    }

    /// Lists the applications and agents that use a layout.
    public func layoutUsages(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ResourceUsagesResponse {
        try await transport.send("GET", ["layouts", id, "usages"], query: .page(limit, offset), fetcher: fetcher)
    }

    // MARK: - Resolution

    /// Returns the theme and layout that apply to an application or an organization unit.
    public func resolve(type: DesignResolveType, id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> DesignResolveResponse {
        try await transport.send(
            "GET",
            ["resolve"],
            query: .management([("type", type.rawValue), ("id", id)]),
            fetcher: fetcher
        )
    }
}
