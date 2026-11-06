// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Narrows ``ThunderIDClient/getAccessibleOrganizationUnits(scope:limit:offset:)``, relative to the
/// current organization unit.
public enum AccessibleOrganizationUnitScope: String {
    /// The current unit and the accessible units that share its parent.
    case siblings
}

/// An organization unit the signed-in user can access.
public struct AccessibleOrganizationUnit: Codable, Equatable, Identifiable {
    public let id: String
    public let handle: String
    public let name: String
    public let logoUrl: String?

    public init(id: String, handle: String, name: String, logoUrl: String? = nil) {
        self.id = id
        self.handle = handle
        self.name = name
        self.logoUrl = logoUrl
    }
}

/// A page of the organization units the signed-in user can access (`GET /users/me/ous`).
public struct AccessibleOrganizationUnitList: Codable, Equatable {
    /// The unit the list is relative to: the one the session was issued for, or the user's own when it
    /// names none. Returned whatever the scope or page.
    public let current: String
    public let organizationUnits: [AccessibleOrganizationUnit]
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int

    public init(
        current: String,
        organizationUnits: [AccessibleOrganizationUnit],
        totalResults: Int,
        startIndex: Int = 1,
        count: Int? = nil
    ) {
        self.current = current
        self.organizationUnits = organizationUnits
        self.totalResults = totalResults
        self.startIndex = startIndex
        self.count = count ?? organizationUnits.count
    }

    private enum CodingKeys: String, CodingKey {
        case current, organizationUnits, totalResults, startIndex, count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try container.decode(String.self, forKey: .current)
        organizationUnits = try container.decodeIfPresent([AccessibleOrganizationUnit].self, forKey: .organizationUnits)
            ?? []
        totalResults = try container.decodeIfPresent(Int.self, forKey: .totalResults) ?? organizationUnits.count
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex) ?? 1
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? organizationUnits.count
    }
}

/// The organization unit the signed-in session was issued for, from its `ouId`, `ouHandle` and `ouName`
/// claims. For display only: never base an authorization decision on it.
public struct CurrentOrganizationUnit: Equatable {
    public let id: String
    public let handle: String?
    public let name: String?

    public init(id: String, handle: String? = nil, name: String? = nil) {
        self.id = id
        self.handle = handle
        self.name = name
    }
}

/// The signed-in user's own organization units.
public extension ThunderIDClient {
    /// Lists the organization units the signed-in user can access (`GET /users/me/ous`), with the user's
    /// own token. `scope` narrows the list relative to the current unit; `limit` and `offset` page it.
    func getAccessibleOrganizationUnits(
        scope: AccessibleOrganizationUnitScope? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> AccessibleOrganizationUnitList {
        try requireInitialized()
        var query = URLComponents()
        query.queryItems = [URLQueryItem].management([
            ("scope", scope?.rawValue),
            ("limit", limit.map(String.init)),
            ("offset", offset.map(String.init))
        ])
        let suffix = query.percentEncodedQuery.map { $0.isEmpty ? "" : "?\($0)" } ?? ""
        return try await httpClient!.get(path: "/users/me/ous\(suffix)")
    }

    /// The organization unit the signed-in session was issued for, read from its `ouId`, `ouHandle` and
    /// `ouName` claims, or `nil` when the session carries none. For display only: the claims are read
    /// without verifying a signature, so never base an authorization decision on them.
    func getCurrentOrganizationUnit() async throws -> CurrentOrganizationUnit? {
        try requireInitialized()
        for claims in try await sessionClaims() {
            if let unit = Self.organizationUnit(from: claims) { return unit }
        }
        return nil
    }
}

extension ThunderIDClient {
    /// The claim sets that can name the session's organization unit, most specific first: the ID token,
    /// the access token (the assertion of an app-native sign-in), and the backend session's user.
    func sessionClaims() async throws -> [[String: AnyCodable]] {
        if let backend {
            let session = try await backend.getSession()
            return session.isSignedIn ? [session.user ?? [:]] : []
        }
        let tokens = [tokenStore?.idToken(), tokenStore?.accessToken()].compactMap { $0 }
        var result = tokens.compactMap { try? decodeJwtToken($0) as [String: AnyCodable] }
        if let user = currentUser { result.append(user.claims) }
        return result
    }

    static func organizationUnit(from claims: [String: AnyCodable]) -> CurrentOrganizationUnit? {
        guard let id = claims["ouId"]?.value as? String, !id.isEmpty else { return nil }
        return CurrentOrganizationUnit(
            id: id,
            handle: claims["ouHandle"]?.value as? String,
            name: claims["ouName"]?.value as? String
        )
    }
}
