// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The payload used to create or update a theme. `theme` is the theme document as JSON.
public struct ThemeRequest: Codable {
    public var handle: String
    public var displayName: String
    public var description: String?
    public var theme: [String: AnyCodable]

    public init(handle: String, displayName: String, theme: [String: AnyCodable], description: String? = nil) {
        self.handle = handle
        self.displayName = displayName
        self.theme = theme
        self.description = description
    }
}

/// A theme.
public struct Theme: Codable {
    public let id: String?
    public let handle: String?
    public let displayName: String?
    public let description: String?
    public let theme: [String: AnyCodable]?
    public let createdAt: String?
    public let updatedAt: String?
    public let isReadOnly: Bool?
}

/// A theme in a listing.
public struct ThemeSummary: Codable {
    public let id: String?
    public let handle: String?
    public let displayName: String?
    public let description: String?
    public let defaultColorScheme: String?
    public let primaryColor: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let isReadOnly: Bool?
}

/// A page of themes.
public struct ThemeListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let themes: [ThemeSummary]
    public let links: [ApiPaginationLink]?
}

/// The payload used to create or update a layout. `layout` is the layout document as JSON.
public struct LayoutRequest: Codable {
    public var handle: String
    public var displayName: String
    public var description: String?
    public var layout: [String: AnyCodable]

    public init(handle: String, displayName: String, layout: [String: AnyCodable], description: String? = nil) {
        self.handle = handle
        self.displayName = displayName
        self.layout = layout
        self.description = description
    }
}

/// A layout.
public struct Layout: Codable {
    public let id: String?
    public let handle: String?
    public let displayName: String?
    public let description: String?
    public let layout: [String: AnyCodable]?
    public let createdAt: String?
    public let updatedAt: String?
    public let isReadOnly: Bool?
}

/// A layout in a listing.
public struct LayoutSummary: Codable {
    public let id: String?
    public let handle: String?
    public let displayName: String?
    public let description: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let isReadOnly: Bool?
}

/// A page of layouts.
public struct LayoutListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let layouts: [LayoutSummary]
    public let links: [ApiPaginationLink]?
}

/// What a design is resolved for.
public enum DesignResolveType: String, Codable, CaseIterable {
    case application = "APP"
    case organizationUnit = "OU"
}

/// The theme and layout that apply to an application or an organization unit.
public struct DesignResolveResponse: Codable {
    public let theme: [String: AnyCodable]?
    public let layout: [String: AnyCodable]?
}
