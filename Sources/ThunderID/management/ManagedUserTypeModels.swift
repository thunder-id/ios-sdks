// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A user type as listed by the ThunderID management API. A user type is identified by its
/// immutable `handle`; `displayName` is not unique.
public struct ManagedUserType: Codable {
    public let id: String
    public let handle: String
    public let displayName: String?
    public let ouId: String?
    public let ouHandle: String?
    public let allowSelfRegistration: Bool?
    public let isReadOnly: Bool?
}

/// A page of user types.
public struct ManagedUserTypeListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let types: [ManagedUserType]
    public let links: [ApiPaginationLink]?
}
