// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Configuration versions, import and export, reached through `ThunderIDClient.configuration`. The
/// collection URLs come from `endpoints.configurationVersions`, `endpoints.import` and
/// `endpoints.export`, otherwise `{baseUrl}/configuration-versions`, `{baseUrl}/import` and
/// `{baseUrl}/export`. Imports and exports can carry secrets, so their bodies are never logged.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ConfigurationAPI {
    let versionsTransport: ManagementTransport
    let importTransport: ManagementTransport
    let exportTransport: ManagementTransport

    /// Returns the captured configuration versions.
    public func versions(fetcher: ThunderIDFetcher? = nil) async throws -> [ConfigurationVersion] {
        try await versionsTransport.send("GET", fetcher: fetcher)
    }

    /// Returns a configuration version.
    public func version(_ version: String, fetcher: ThunderIDFetcher? = nil) async throws -> ConfigurationVersion {
        try await versionsTransport.send("GET", [version], fetcher: fetcher)
    }

    /// Captures the current configuration as a version and returns it. When nothing changed since the
    /// last version, the server returns that version with `unchanged` set.
    public func createVersion(
        _ request: CaptureConfigurationVersionRequest = .init(),
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ConfigurationVersion {
        try await versionsTransport.send("POST", body: request, fetcher: fetcher)
    }

    /// Exports resources as a declarative document.
    public func exportConfiguration(_ request: ExportRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ExportResponse {
        try await exportTransport.send("POST", body: request, fetcher: fetcher)
    }

    /// Imports a declarative document, or reports what it would do on a dry run.
    public func importConfiguration(_ request: ImportRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> ImportResponse {
        try await importTransport.send("POST", body: request, fetcher: fetcher)
    }

    /// Deletes a resource that was imported from a declarative file.
    public func deleteImportedConfiguration(
        _ request: DeleteImportedConfigurationRequest,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> DeleteImportedConfigurationResponse {
        try await importTransport.send("POST", ["delete"], body: request, fetcher: fetcher)
    }
}
