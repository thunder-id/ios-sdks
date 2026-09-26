// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Sends management API requests for one resource collection. The collection URL comes from the
/// `endpoints` override when set, otherwise `{baseUrl}/{collection}`.
struct ManagementTransport {
    let httpClient: HTTPClient
    let collectionUrl: String
    let fetcher: ThunderIDFetcher?

    func list<T: Decodable>(query: [URLQueryItem], fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(method: "GET", url: url(id: nil, query: query), fetcher: fetcher ?? self.fetcher)
    }

    func get<T: Decodable>(id: String, query: [URLQueryItem] = [], fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(method: "GET", url: url(id: id, query: query), fetcher: fetcher ?? self.fetcher)
    }

    func create<T: Decodable, Body: Encodable>(_ body: Body, fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(
            method: "POST",
            url: url(id: nil, query: []),
            body: try JSONEncoder().encode(body),
            fetcher: fetcher ?? self.fetcher
        )
    }

    func update<T: Decodable, Body: Encodable>(id: String, _ body: Body, fetcher: ThunderIDFetcher?) async throws -> T {
        try await httpClient.send(
            method: "PUT",
            url: url(id: id, query: []),
            body: try JSONEncoder().encode(body),
            fetcher: fetcher ?? self.fetcher
        )
    }

    func delete(id: String, fetcher: ThunderIDFetcher?) async throws {
        let _: EmptyResponse = try await httpClient.send(
            method: "DELETE",
            url: url(id: id, query: []),
            fetcher: fetcher ?? self.fetcher
        )
    }

    private func url(id: String?, query: [URLQueryItem]) throws -> URL {
        if let id, id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ThunderIDError(code: .invalidInput, message: "A resource identifier is required")
        }
        var base = collectionUrl
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if let id {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id
            base += "/\(encoded)"
        }
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
}
