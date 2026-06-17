import Foundation
import CryptoKit

/// Fetches and caches the server JWKS. Supports key rotation (spec §11.4).
final class JWKSCache {
    private let httpClient: HTTPClient
    private var cachedKeys: [JWK] = []
    private var cacheExpiry: Date = .distantPast
    private let minCacheTTL: TimeInterval = 300 // 5 minutes

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func getKeys(forceRefresh: Bool = false) async throws -> [JWK] {
        if !forceRefresh && Date() < cacheExpiry && !cachedKeys.isEmpty {
            return cachedKeys
        }
        let response: JWKSResponse = try await httpClient.get(path: "/oauth2/jwks", requiresAuth: false)
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
