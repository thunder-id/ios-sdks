// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Notification template management operations, reached through `ThunderIDClient.notificationTemplates`.
/// The collection URL comes from `endpoints.notificationTemplates`, otherwise
/// `{baseUrl}/notification-templates`; a channel's templates are under `{channel}/templates`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct NotificationTemplatesAPI {
    let transport: ManagementTransport

    /// Returns a page of a channel's templates.
    public func list(
        channel: NotificationChannel,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> NotificationTemplateListResponse {
        try await transport.send("GET", [channel.rawValue, "templates"], query: .page(limit, offset), fetcher: fetcher)
    }

    /// Returns a template.
    public func get(channel: NotificationChannel, id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> NotificationTemplate {
        try await transport.send("GET", [channel.rawValue, "templates", id], fetcher: fetcher)
    }

    /// Creates a template and returns it.
    public func create(
        channel: NotificationChannel,
        _ template: CreateNotificationTemplateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> NotificationTemplate {
        try await transport.send("POST", [channel.rawValue, "templates"], body: template, fetcher: fetcher)
    }

    /// Updates a template and returns it.
    public func update(
        channel: NotificationChannel,
        id: String,
        _ template: UpdateNotificationTemplateRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> NotificationTemplate {
        try await transport.send("PUT", [channel.rawValue, "templates", id], body: template, fetcher: fetcher)
    }

    /// Deletes a template.
    public func delete(channel: NotificationChannel, id: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", [channel.rawValue, "templates", id], fetcher: fetcher)
    }
}
