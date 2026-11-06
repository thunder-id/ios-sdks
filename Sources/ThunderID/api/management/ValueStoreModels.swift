// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A variable: a named value that resource definitions reference.
public struct Variable: Codable, Equatable {
    public let name: String
    public let value: String
    public let description: String?
    public let createdAt: String?
    public let updatedAt: String?
}

/// A page of variables.
public struct VariableListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let variables: [Variable]
    public let links: [ApiPaginationLink]?
}

/// A secret. Its value is write-only: the server only says whether one is set.
public struct Secret: Codable, Equatable {
    public let name: String
    public let exists: Bool
    public let description: String?
    public let createdAt: String?
    public let updatedAt: String?
}

/// A page of secrets.
public struct SecretListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let secrets: [Secret]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a variable or a secret.
public struct ValueEntryRequest: Codable, Equatable {
    public var name: String
    public var value: String
    public var description: String?

    public init(name: String, value: String, description: String? = nil) {
        self.name = name
        self.value = value
        self.description = description
    }
}

/// The payload used to update a variable or a secret. Updating one that does not exist creates it.
public struct ValueEntryUpdateRequest: Codable, Equatable {
    public var value: String
    public var description: String?

    public init(value: String, description: String? = nil) {
        self.value = value
        self.description = description
    }
}

extension ManagementTransport {
    /// The query of a variable or secret listing: paging, the exact `names` (comma separated) and `filter`.
    static func valueQuery(_ limit: Int?, _ offset: Int?, _ names: [String]?, _ filter: String?) -> [URLQueryItem] {
        .page(limit, offset) + .management([("names", names?.joined(separator: ",")), ("filter", filter)])
    }
}
