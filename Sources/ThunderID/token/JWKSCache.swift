// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation

/// Fetches and caches the server JWKS. Supports key rotation (spec §11.4).
final class JWKSCache {
    private let httpClient: HTTPClient
    /// Where the keys are: the server's advertised `jwks_uri`. Without it, `/oauth2/jwks` under `baseUrl`.
    private let endpoint: (() async throws -> URL)?
    private var cachedKeys: [JWK] = []
    private var cacheExpiry: Date = .distantPast
    private let minCacheTTL: TimeInterval = 300 // 5 minutes

    init(httpClient: HTTPClient, endpoint: (() async throws -> URL)? = nil) {
        self.httpClient = httpClient
        self.endpoint = endpoint
    }

    func getKeys(forceRefresh: Bool = false) async throws -> [JWK] {
        if !forceRefresh && Date() < cacheExpiry && !cachedKeys.isEmpty {
            return cachedKeys
        }
        let response: JWKSResponse
        if let endpoint {
            response = try await httpClient.get(url: try await endpoint(), requiresAuth: false)
        } else {
            response = try await httpClient.get(path: "/oauth2/jwks", requiresAuth: false)
        }
        cachedKeys = response.keys
        cacheExpiry = Date().addingTimeInterval(minCacheTTL)
        return cachedKeys
    }
}

struct JWKSResponse: Codable {
    let keys: [JWK]
}

struct JWK: Codable {
    let kty: String
    let kid: String?
    let use: String?
    let alg: String?
    let modulus: String?
    let exponent: String?

    enum CodingKeys: String, CodingKey {
        case kty, kid, use, alg
        case modulus = "n"
        case exponent = "e"
    }
}
