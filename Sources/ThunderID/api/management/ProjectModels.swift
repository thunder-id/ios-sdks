// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A project: a grouping of identity configuration. Every project includes the default organization
/// unit. Only the Control Plane serves projects.
public struct Project: Codable, Equatable {
    public let id: String
    /// Immutable, human-readable identifier, unique across projects.
    public let handle: String
    public let displayName: String
    public let description: String?
    /// When the project was created, as an RFC 3339 date-time.
    public let createdAt: String?
}

/// A page of projects, oldest first.
public struct ProjectListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let projects: [Project]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create a project.
public struct CreateProjectRequest: Codable, Equatable {
    /// An id to keep, such as one another system already uses for the project. The server generates
    /// one when it is `nil`.
    public var id: String?
    /// Lowercase letters, numbers, hyphens and underscores, starting and ending with a letter or a number.
    public var handle: String
    public var displayName: String
    public var description: String?

    public init(id: String? = nil, handle: String, displayName: String, description: String? = nil) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.description = description
    }
}

/// The payload used to update a project. The handle cannot change; when sent, it must be the current one.
public struct UpdateProjectRequest: Codable, Equatable {
    public var handle: String?
    public var displayName: String
    public var description: String?

    public init(displayName: String, description: String? = nil, handle: String? = nil) {
        self.handle = handle
        self.displayName = displayName
        self.description = description
    }
}
