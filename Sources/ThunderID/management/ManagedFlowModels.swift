// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A flow definition as listed by the ThunderID management API.
public struct ManagedFlow: Codable {
    public let id: String
    public let handle: String
    public let name: String
    public let flowType: String
    public let activeVersion: Int?
    public let isReadOnly: Bool?
    public let createdAt: String?
    public let updatedAt: String?
}

/// A page of flows.
public struct ManagedFlowListResponse: Codable {
    public let totalResults: Int
    public let startIndex: Int
    public let count: Int
    public let flows: [ManagedFlow]
    public let links: [ApiPaginationLink]?
}
