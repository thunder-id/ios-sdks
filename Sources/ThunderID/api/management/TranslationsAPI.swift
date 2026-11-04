// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The languages the server holds translations for.
public struct LanguageListResponse: Codable {
    public let languages: [String]
}

/// The translations of a language, keyed by namespace and then by key.
public struct LanguageTranslations: Codable {
    public let language: String
    public let totalResults: Int?
    public let translations: [String: [String: String]]
}

/// One translation.
public struct Translation: Codable, Equatable {
    public let language: String
    public let namespace: String
    public let key: String
    public let value: String
}

/// Translation management operations, reached through `ThunderIDClient.translations`. The collection
/// URL comes from `endpoints.i18n`, otherwise `{baseUrl}/i18n`; a language's translations are under
/// `languages/{language}/translations`.
/// Each call accepts an optional `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`.
public struct TranslationsAPI {
    let transport: ManagementTransport

    /// Returns the languages the server holds translations for.
    public func languages(fetcher: ThunderIDFetcher? = nil) async throws -> LanguageListResponse {
        try await transport.send("GET", ["languages"], fetcher: fetcher)
    }

    /// Returns a language's translations, with the server's defaults filled in.
    /// - Parameter namespace: Only this namespace.
    public func resolveTranslations(
        language: String,
        namespace: String? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> LanguageTranslations {
        try await transport.send(
            "GET",
            translationsPath(language) + ["resolve"],
            query: .management([("namespace", namespace)]),
            fetcher: fetcher
        )
    }

    /// Returns one translation, with the server's default filled in.
    public func resolveTranslation(
        language: String,
        namespace: String,
        key: String,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> Translation {
        try await transport.send("GET", keyPath(language, namespace, key) + ["resolve"], fetcher: fetcher)
    }

    /// Sets a language's translations, keyed by namespace and then by key, and returns them.
    public func setTranslations(
        language: String,
        _ translations: [String: [String: String]],
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> LanguageTranslations {
        try await transport.send(
            "POST",
            translationsPath(language),
            body: ["translations": translations],
            fetcher: fetcher
        )
    }

    /// Deletes a language's custom translations, so the server's defaults apply again.
    public func deleteTranslations(language: String, fetcher: ThunderIDFetcher? = nil) async throws {
        try await transport.sendWithoutResult("DELETE", translationsPath(language), fetcher: fetcher)
    }

    /// Sets one translation and returns it.
    public func setTranslation(
        language: String,
        namespace: String,
        key: String,
        value: String,
        fetcher: ThunderIDFetcher? = nil
    ) async throws -> Translation {
        try await transport.send("POST", keyPath(language, namespace, key), body: ["value": value], fetcher: fetcher)
    }

    /// Deletes one custom translation, so the server's default applies again.
    public func deleteTranslation(
        language: String,
        namespace: String,
        key: String,
        fetcher: ThunderIDFetcher? = nil
    ) async throws {
        try await transport.sendWithoutResult("DELETE", keyPath(language, namespace, key), fetcher: fetcher)
    }

    private func translationsPath(_ language: String) -> [String] {
        ["languages", language, "translations"]
    }

    private func keyPath(_ language: String, _ namespace: String, _ key: String) -> [String] {
        translationsPath(language) + ["ns", namespace, "keys", key]
    }
}
