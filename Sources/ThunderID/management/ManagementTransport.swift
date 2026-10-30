// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Sends management API requests for one resource collection. The collection URL comes from the
/// `endpoints` override when set, otherwise `{baseUrl}/{collection}`. Server-level requests, such as
/// the administration flows, always go to `baseUrl`. With sign-in on a backend, `baseUrl` here is the
/// backend's proxy (`{baseUrl}{endpoints.backend.proxy}`), which maps the requests to the API.
struct ManagementTransport {
    let httpClient: HTTPClient
    /// The server URL. Server-level requests go here whatever `collectionUrl` is.
    let baseUrl: String
    let collectionUrl: String
    let fetcher: ThunderIDFetcher?
    /// Whether this collection's requests or responses can carry a credential, such as a secret value or
    /// a connection's client secret. Their bodies are then never logged.
    var isSensitive = false

    func list<T: Decodable>(query: [URLQueryItem], fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(
            method: "GET",
            url: url(id: nil, query: query),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    func get<T: Decodable>(id: String, query: [URLQueryItem] = [], fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(
            method: "GET",
            url: url(id: id, query: query),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    func create<T: Decodable, Body: Encodable>(_ body: Body, fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(
            method: "POST",
            url: url(id: nil, query: []),
            body: try JSONEncoder().encode(body),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    func update<T: Decodable, Body: Encodable>(id: String, _ body: Body, fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(
            method: "PUT",
            url: url(id: id, query: []),
            body: try JSONEncoder().encode(body),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    func delete(id: String, fetcher: ThunderIDFetcher?) async throws {
        let _: EmptyResponse = try await httpClient.send(
            method: "DELETE",
            url: url(id: id, query: []),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    /// Reads a sub-collection of one resource, such as `{collection}/{id}/members`.
    func related<T: Decodable>(
        id: String,
        subPath: String,
        query: [URLQueryItem],
        fetcher: ThunderIDFetcher?
    ) async throws -> T {
        try await httpClient.send(
            method: "GET",
            url: url(id: id, subPath: subPath, query: query),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    /// Posts to an action on one resource, such as `{collection}/{id}/members/add`.
    func action<T: Decodable, Body: Encodable>(
        id: String,
        subPath: String,
        _ body: Body,
        fetcher: ThunderIDFetcher?
    ) async throws -> T {
        try await httpClient.send(
            method: "POST",
            url: url(id: id, subPath: subPath, query: []),
            body: try JSONEncoder().encode(body),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    /// Sends a request to a server-level path, `{baseUrl}/{path}`, whatever collection URL this
    /// transport addresses.
    func server<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        fetcher: ThunderIDFetcher?
    ) async throws -> T {
        try await httpClient.send(
            method: method,
            url: Self.resolve("\(try requireBaseUrl())/\(path)", query: query),
            body: body,
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    /// Sends a request to `{collectionUrl}/{segments...}`, each segment percent-encoded on its own (a
    /// slash inside a segment is encoded too). Use ``ManagementPath/tree(_:)`` for an organization unit
    /// handle path, whose slashes separate segments.
    func send<T: Decodable>(
        _ method: String,
        _ segments: [String] = [],
        query: [URLQueryItem] = [],
        fetcher: ThunderIDFetcher?
    ) async throws -> T {
        try await httpClient.send(
            method: method,
            url: url(segments: segments, query: query),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    /// Sends `body` as JSON to `{collectionUrl}/{segments...}`. See ``send(_:_:query:fetcher:)``.
    func send<T: Decodable, Body: Encodable>(
        _ method: String,
        _ segments: [String] = [],
        query: [URLQueryItem] = [],
        body: Body,
        fetcher: ThunderIDFetcher?
    ) async throws -> T {
        try await httpClient.send(
            method: method,
            url: url(segments: segments, query: query),
            body: try JSONEncoder().encode(body),
            isSensitive: isSensitive,
            fetcher: fetcher ?? self.fetcher
        )
    }

    /// Sends a request whose success has no body, such as a `DELETE`.
    func sendWithoutResult(_ method: String, _ segments: [String] = [], fetcher: ThunderIDFetcher?) async throws {
        let _: EmptyResponse = try await send(method, segments, fetcher: fetcher)
    }

    private func url(segments: [String], query: [URLQueryItem]) throws -> URL {
        var base = collectionUrl
        while base.hasSuffix("/") {
            base.removeLast()
        }
        for segment in segments {
            guard !segment.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ThunderIDError(code: .invalidInput, message: "A resource identifier is required")
            }
            base += "/" + (segment.addingPercentEncoding(withAllowedCharacters: ManagementPath.allowed) ?? segment)
        }
        return try Self.resolve(base, query: query)
    }

    /// `baseUrl` without trailing slashes. Throws when it is empty, since a collection URL alone cannot
    /// address a server-level path.
    func requireBaseUrl(_ message: String = "A `baseUrl` is required for this request") throws -> String {
        var base = baseUrl.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard !base.isEmpty else {
            throw ThunderIDError(code: .invalidConfiguration, message: message)
        }
        return base
    }

    private func url(id: String?, subPath: String? = nil, query: [URLQueryItem]) throws -> URL {
        if let id, id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ThunderIDError(code: .invalidInput, message: "A resource identifier is required")
        }
        var base = collectionUrl
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if let id {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: ManagementPath.allowed) ?? id
            base += "/\(encoded)"
            if let subPath {
                base += "/\(subPath)"
            }
        }
        return try Self.resolve(base, query: query)
    }

    private static func resolve(_ base: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid management URL: \(base)")
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw ThunderIDError(code: .invalidConfiguration, message: "Invalid management URL: \(base)")
        }
        return url
    }
}

extension Array where Element == URLQueryItem {
    /// Builds query items, dropping `nil` values.
    static func management(_ pairs: [(String, String?)]) -> [URLQueryItem] {
        pairs.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    }

    /// The `limit` and `offset` of a paged list, each left out when `nil`.
    static func page(_ limit: Int?, _ offset: Int?) -> [URLQueryItem] {
        management([("limit", limit.map(String.init)), ("offset", offset.map(String.init))])
    }
}

/// Builds the path segments of management URLs.
enum ManagementPath {
    /// The characters a path segment keeps unencoded: a slash is encoded, so it cannot add a segment.
    static let allowed = CharacterSet.urlPathAllowed.subtracting(["/"])

    /// The segments of an organization unit handle path such as `a/b/c`, each encoded on its own so the
    /// slashes between them stay. Leading and trailing slashes are dropped. Throws
    /// ``ThunderIDErrorCode/invalidInput`` for an empty path or an empty segment (`a//b`).
    static func tree(_ path: String) throws -> [String] {
        var trimmed = Substring(path.trimmingCharacters(in: .whitespaces))
        while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
        while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !trimmed.isEmpty, segments.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw ThunderIDError(
                code: .invalidInput,
                message: "An organization unit path is required, as handles separated by slashes"
            )
        }
        return segments
    }
}
