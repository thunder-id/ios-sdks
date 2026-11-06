// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The channel a notification template is sent through.
public enum NotificationChannel: String, Codable, CaseIterable {
    case email
    case sms
}

/// A template in a listing.
public struct NotificationTemplateSummary: Codable {
    public let id: String
    public let handle: String
    public let displayName: String
    public let description: String?
    /// The template's URL.
    public let `self`: String?
}

/// A page of templates.
public struct NotificationTemplateListResponse: Codable {
    public let totalResults: Int?
    public let startIndex: Int?
    public let count: Int?
    public let templates: [NotificationTemplateSummary]
    public let links: [ApiPaginationLink]?
}

/// What a template sends. `subject` is for email only.
public struct NotificationTemplateContent: Codable, Equatable {
    public var subject: String?
    public var body: String

    public init(subject: String? = nil, body: String) {
        self.subject = subject
        self.body = body
    }
}

/// How an email template is drawn.
public struct NotificationTemplateDesign: Codable, Equatable {
    /// `light` or `dark`.
    public var colorScheme: String?

    public init(colorScheme: String? = nil) {
        self.colorScheme = colorScheme
    }
}

/// An email or SMS template.
public struct NotificationTemplate: Codable {
    public let id: String
    public let ouId: String
    public let handle: String
    public let isReadOnly: Bool?
    public let displayName: String
    public let description: String?
    /// Email only.
    public let design: NotificationTemplateDesign?
    public let content: NotificationTemplateContent
}

/// The payload used to create a template.
public struct CreateNotificationTemplateRequest: Codable {
    public var handle: String
    public var ouId: String
    public var displayName: String
    public var description: String?
    /// Email only.
    public var design: NotificationTemplateDesign?
    public var content: NotificationTemplateContent

    public init(
        handle: String,
        ouId: String,
        displayName: String,
        content: NotificationTemplateContent,
        description: String? = nil,
        design: NotificationTemplateDesign? = nil
    ) {
        self.handle = handle
        self.ouId = ouId
        self.displayName = displayName
        self.content = content
        self.description = description
        self.design = design
    }
}

/// The payload used to update a template. The handle and organization unit cannot change.
public struct UpdateNotificationTemplateRequest: Codable {
    public var displayName: String
    public var description: String?
    /// Email only.
    public var design: NotificationTemplateDesign?
    public var content: NotificationTemplateContent

    public init(
        displayName: String,
        content: NotificationTemplateContent,
        description: String? = nil,
        design: NotificationTemplateDesign? = nil
    ) {
        self.displayName = displayName
        self.content = content
        self.description = description
        self.design = design
    }
}
