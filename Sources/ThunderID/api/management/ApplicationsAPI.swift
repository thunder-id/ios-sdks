// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Application management operations, reached through `ThunderIDClient.applications`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct ApplicationsAPI {
    let transport: ManagementTransport

    /// Returns a page of applications.
    /// - Parameter projectId: Lists the applications the project's root organization unit owns,
    ///   followed by the applications shared into it.
    public func list(
        limit: Int? = nil,
        offset: Int? = nil,
        projectId: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> ApplicationListResponse {
        try await transport.list(
            query: .management([
                ("limit", limit.map(String.init)),
                ("offset", offset.map(String.init)),
                ("projectId", projectId)
            ]),
            fetcher: fetcher
        )
    }

    /// Returns a single application.
    public func get(id: String, fetcher: ThunderIDFetcher? = nil) async throws -> Application {
        try await transport.get(id: id, fetcher: fetcher)
    }

    /// Creates an application and returns it as the server stored it.
    public func create(_ application: ApplicationRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Application {
        try await transport.create(application, fetcher: fetcher)
    }

    /// Replaces an application's mutable fields and returns the updated application.
    public func update(id: String, _ application: ApplicationRequest, fetcher: ThunderIDFetcher? = nil) async throws
        -> Application {
        try await transport.update(id: id, application, fetcher: fetcher)
    }

    /// Deletes an application. In `.flow` mode the configured application deletion flow runs instead,
    /// revoking what the application was granted before the record goes.
    public func delete(
        id: String,
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        let ran = try await transport.runAdministrationFlow(
            administrationMode,
            .applicationDeletion,
            inputs: [AdministrationFlowInput.application: id],
            action: "application deletion",
            fetcher: fetcher
        )
        if ran != nil { return }
        try await transport.delete(id: id, fetcher: fetcher)
    }

    /// Reads a client ID metadata document (CIMD) through the server and returns what it declares, so an
    /// application can be registered from it. Sent to `{baseUrl}/cimd/preview`.
    /// - Parameter clientId: The client ID: the URL of the client's metadata document.
    public func previewCimdDocument(clientId: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> CimdPreviewResponse {
        try await transport.server(
            method: "POST",
            path: "cimd/preview",
            body: try JSONEncoder().encode(["clientId": clientId]),
            fetcher: fetcher
        )
    }

    /// Gives an application a new OAuth client secret. In `.flow` mode the configured secret
    /// regeneration flow rotates it, revoking what the old secret was used for; otherwise a new secret
    /// is generated here and saved on the application. Fails with ``ThunderIDErrorCode/invalidInput``
    /// before saving anything when the application has no OAuth client.
    public func regenerateClientSecret(
        id: String,
        administrationMode: AdministrationMode = .native,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> RegenerateClientSecretResult {
        if let produced = try await transport.runAdministrationFlow(
            administrationMode,
            .secretRegeneration,
            inputs: [AdministrationFlowInput.application: id],
            action: "client secret regeneration",
            fetcher: fetcher
        ) {
            guard let clientSecret = produced[AdministrationFlowData.clientSecret], !clientSecret.isEmpty else {
                throw ThunderIDError(
                    code: .administrationFlowFailed,
                    message: "The client secret regeneration flow completed without returning a secret."
                )
            }
            return RegenerateClientSecretResult(application: nil, clientSecret: clientSecret)
        }
        var request = try await get(id: id, fetcher: fetcher).request
        let inbound = request.inboundAuthConfig ?? []
        guard inbound.contains(where: { $0.type == "oauth2" }) else {
            throw ThunderIDError(
                code: .invalidInput,
                message: "The application has no OAuth client, so it has no client secret to regenerate."
            )
        }
        let clientSecret = try SecretGenerator.generate()
        request.inboundAuthConfig = inbound.map { entry in
            guard entry.type == "oauth2" else { return entry }
            var rotated = entry
            rotated.config.clientSecret = clientSecret
            return rotated
        }
        let application = try await update(id: id, request, fetcher: fetcher)
        return RegenerateClientSecretResult(application: application, clientSecret: clientSecret)
    }

    /// Gives an application a new flow secret, generated here and saved on the application.
    public func regenerateFlowSecret(id: String, fetcher: ThunderIDFetcher? = nil) async throws
        -> RegenerateFlowSecretResult {
        // `request` leaves out the fields the server sets (`id`, `createdAt`, `updatedAt`).
        var request = try await get(id: id, fetcher: fetcher).request
        let flowSecret = try SecretGenerator.generate()
        request.flowSecret = flowSecret
        let application = try await update(id: id, request, fetcher: fetcher)
        return RegenerateFlowSecretResult(application: application, flowSecret: flowSecret)
    }
}
