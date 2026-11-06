// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A resource a configuration version left out, and why.
public struct ConfigurationVersionSkip: Codable, Equatable {
    public let resourceType: String?
    public let resourceId: String?
    public let error: String?
    public let code: String?
}

/// A captured configuration version.
public struct ConfigurationVersion: Codable {
    public let number: Int?
    public let version: String?
    public let name: String?
    public let note: String?
    /// Whether the capture matched the previous version, so no new version was recorded.
    public let unchanged: Bool?
    public let current: Bool?
    public let createdAt: String?
    public let createdBy: ConfigurationActor?
    /// The captured resources, as a declarative document.
    public let resources: String?
    public let references: [ValueReference]?
    public let skipped: [ConfigurationVersionSkip]?
}

/// The payload used to capture the current configuration as a version.
public struct CaptureConfigurationVersionRequest: Codable, Equatable {
    public var name: String?
    public var note: String?
    /// Whether to make the captured version the current one.
    public var current: Bool?

    public init(name: String? = nil, note: String? = nil, current: Bool? = nil) {
        self.name = name
        self.note = note
        self.current = current
    }
}

/// How an export is shaped.
public struct ExportOptions: Codable, Equatable {
    public var includeMetadata: Bool?
    public var includeDependencies: Bool?
    /// Currently `yaml`.
    public var format: String?

    public init(includeMetadata: Bool? = nil, includeDependencies: Bool? = nil, format: String? = nil) {
        self.includeMetadata = includeMetadata
        self.includeDependencies = includeDependencies
        self.format = format
    }
}

/// What to export: the identifiers of each kind of resource (`["*"]` for all of a kind).
public struct ExportRequest: Codable, Equatable {
    public var applications: [String]?
    public var connections: [String]?
    public var userTypes: [String]?
    public var agentTypes: [String]?
    public var organizationUnits: [String]?
    public var users: [String]?
    public var groups: [String]?
    public var resourceServers: [String]?
    public var authorizationDetailTypes: [String]?
    public var roles: [String]?
    public var flows: [String]?
    public var translations: [String]?
    public var layouts: [String]?
    public var themes: [String]?
    public var credentialConfigurations: [String]?
    public var presentationDefinitions: [String]?
    public var notificationTemplates: [String]?
    public var options: ExportOptions?

    public init() {}
}

/// An export: the resources as a declarative document, and the environment variables it references.
public struct ExportResponse: Codable, Equatable {
    public let resources: String
    public let environmentVariables: String

    private enum CodingKeys: String, CodingKey {
        case resources
        case environmentVariables = "environment_variables"
    }
}

/// A resource to delete as part of an import.
public struct ImportDeletion: Codable, Equatable {
    public var resourceType: String
    public var id: String

    public init(resourceType: String, id: String) {
        self.resourceType = resourceType
        self.id = id
    }
}

/// How an import is applied.
public struct ImportOptions: Codable, Equatable {
    /// Whether to update resources that exist.
    public var upsert: Bool?
    public var continueOnError: Bool?
    /// Currently `runtime`.
    public var target: String?

    public init(upsert: Bool? = nil, continueOnError: Bool? = nil, target: String? = nil) {
        self.upsert = upsert
        self.continueOnError = continueOnError
        self.target = target
    }
}

/// What to import: a declarative document, the values of the `{{.NAME}}` variables it references, and
/// resources to delete. The variables can hold secrets, so the request is never logged.
public struct ImportRequest: Codable {
    public var content: String?
    public var variables: [String: AnyCodable]?
    public var dryRun: Bool?
    public var deletions: [ImportDeletion]?
    public var options: ImportOptions?

    public init(
        content: String? = nil,
        variables: [String: AnyCodable]? = nil,
        dryRun: Bool? = nil,
        deletions: [ImportDeletion]? = nil,
        options: ImportOptions? = nil
    ) {
        self.content = content
        self.variables = variables
        self.dryRun = dryRun
        self.deletions = deletions
        self.options = options
    }
}

/// The totals of an import.
public struct ImportSummary: Codable, Equatable {
    public let totalDocuments: Int
    public let deleted: Int?
    public let imported: Int
    public let failed: Int
    public let importedAt: String
}

/// What happened to one resource of an import.
public struct ImportItemOutcome: Codable, Equatable {
    public let resourceType: String
    public let resourceId: String?
    public let resourceName: String?
    /// `create` or `update`.
    public let operation: String?
    /// `success` or `failed`.
    public let status: String
    public let code: String?
    public let message: String?
}

/// What an import did.
public struct ImportResponse: Codable {
    public let summary: ImportSummary
    public let results: [ImportItemOutcome]
}

/// A resource imported from a declarative file, to delete.
public struct DeleteImportedConfigurationRequest: Codable, Equatable {
    public var resourceType: String
    public var resourceKey: String

    public init(resourceType: String, resourceKey: String) {
        self.resourceType = resourceType
        self.resourceKey = resourceKey
    }
}

/// What deleting an imported resource removed.
public struct DeleteImportedConfigurationResponse: Codable, Equatable {
    public let resourceType: String
    public let resourceKey: String
    public let deletedFile: String
}
