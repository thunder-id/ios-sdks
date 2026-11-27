// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderIDSwiftUI

/// One token as shown in the inspector.
struct TokenItem: Identifiable {
    let id: String
    let name: String
    let meta: String
    let value: String
}

/// The tokens and claims of the current session, read through the SDK and the storage adapter.
struct SessionSnapshot {
    var tokens: [TokenItem] = []
    var claims: [(key: String, value: String)] = []
    var claimsSource = ""
    var issuedAt: Date?
    var expiresAt: Date?

    static let empty = SessionSnapshot()

    @MainActor
    static func load(client: ThunderIDClient, storage: PlaygroundStorage) async -> SessionSnapshot {
        guard (try? await client.isSignedIn()) == true,
              let access = try? await client.getAccessToken() else { return .empty }
        var snapshot = SessionSnapshot()
        let idToken = storage.retrieve(key: PlaygroundStorage.Key.idToken)
        let refresh = storage.retrieve(key: PlaygroundStorage.Key.refreshToken)
        snapshot.tokens.append(TokenItem(id: "access", name: "Access token", meta: jwtMeta(access), value: access))
        if let idToken {
            snapshot.tokens.append(TokenItem(id: "id", name: "ID token", meta: jwtMeta(idToken), value: idToken))
        }
        if let refresh {
            snapshot.tokens.append(
                TokenItem(id: "refresh", name: "Refresh token", meta: "opaque · rotates", value: refresh)
            )
        }
        let accessClaims = decode(access, with: client)
        let source = idToken.map { decode($0, with: client) } ?? accessClaims
        snapshot.claimsSource = idToken == nil ? "Access token claims" : "ID token claims"
        snapshot.claims = source
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: render($0.value.value)) }
        snapshot.issuedAt = date(accessClaims["iat"])
        snapshot.expiresAt = date(accessClaims["exp"]) ?? storage.accessTokenExpiry
        return snapshot
    }

    private static func date(_ claim: AnyCodable?) -> Date? {
        (claim?.value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    private static func decode(_ token: String, with client: ThunderIDClient) -> [String: AnyCodable] {
        (try? client.decodeJwtToken(token) as [String: AnyCodable]) ?? [:]
    }

    /// "JWT · RS256 · typ at+jwt" from the token header, or "opaque" when it is not a JWT.
    private static func jwtMeta(_ token: String) -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return "opaque" }
        var header = String(parts[0])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while header.count % 4 != 0 { header += "=" }
        guard let data = Data(base64Encoded: header),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alg = json["alg"] as? String else { return "JWT" }
        return "JWT · \(alg)" + ((json["typ"] as? String).map { " · typ \($0)" } ?? "")
    }

    private static func render(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case let list as [AnyCodable]:
            return "[" + list.map { render($0.value) }.joined(separator: ", ") + "]"
        case let dict as [String: AnyCodable]:
            return "{" + dict.keys.sorted().joined(separator: ", ") + "}"
        default:
            return "\(value)"
        }
    }
}
