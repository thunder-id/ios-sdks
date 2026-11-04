// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A claim a credential configuration issues.
public struct CredentialClaim: Codable, Equatable {
    public var name: String
    public var displayName: String?

    public init(name: String, displayName: String? = nil) {
        self.name = name
        self.displayName = displayName
    }
}

/// How a wallet shows a credential.
public struct CredentialDisplay: Codable, Equatable {
    public var locale: String?
    public var logoUri: String?

    public init(locale: String? = nil, logoUri: String? = nil) {
        self.locale = locale
        self.logoUri = logoUri
    }
}

/// An OpenID4VCI credential configuration: a credential type the issuer can issue. A listing returns
/// only the summary fields (`id`, `handle`, `ouId`, `ouHandle`, `format`, `vct` and `name`).
public struct CredentialConfiguration: Codable, Equatable {
    public let id: String
    public let handle: String
    public let ouId: String
    /// The organization unit's handle, resolved for display.
    public let ouHandle: String?
    public let name: String?
    public let description: String?
    /// The credential format, such as `dc+sd-jwt`.
    public let format: String
    /// The verifiable credential type URI.
    public let vct: String
    public let claims: [CredentialClaim]?
    public let display: CredentialDisplay?
    public let validitySeconds: Int?
}

/// The payload used to create or replace a credential configuration.
public struct CredentialConfigurationRequest: Codable, Equatable {
    public var handle: String
    public var ouId: String
    public var vct: String
    public var name: String?
    public var description: String?
    /// The credential format. The server uses `dc+sd-jwt` when it is `nil`.
    public var format: String?
    public var claims: [CredentialClaim]?
    public var display: CredentialDisplay?
    public var validitySeconds: Int?

    public init(
        handle: String,
        ouId: String,
        vct: String,
        name: String? = nil,
        description: String? = nil,
        format: String? = nil,
        claims: [CredentialClaim]? = nil,
        display: CredentialDisplay? = nil,
        validitySeconds: Int? = nil
    ) {
        self.handle = handle
        self.ouId = ouId
        self.vct = vct
        self.name = name
        self.description = description
        self.format = format
        self.claims = claims
        self.display = display
        self.validitySeconds = validitySeconds
    }
}
