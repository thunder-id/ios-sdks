// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An OpenID4VP presentation definition: what the verifier asks a wallet to present. A listing returns
/// only the summary fields (`id`, `handle`, `ouId`, `ouHandle`, `name`, `vct` and `format`).
public struct PresentationDefinition: Codable, Equatable {
    public let id: String
    public let handle: String
    public let ouId: String
    /// The organization unit's handle, resolved for display.
    public let ouHandle: String?
    public let name: String?
    public let description: String?
    /// The verifiable credential type URI.
    public let vct: String
    /// The credential format, such as `dc+sd-jwt`.
    public let format: String
    public let requestedClaims: [String]?
    public let mandatoryClaims: [String]?
    public let optionalClaims: [String]?
    /// The values each claim must hold, by claim name.
    public let claimValues: [String: [String]]?
    public let enforceTrustedIssuer: Bool?
    public let trustedAuthorities: [String]?
}

/// The payload used to create or replace a presentation definition.
public struct PresentationDefinitionRequest: Codable, Equatable {
    public var handle: String
    public var ouId: String
    public var vct: String
    public var name: String?
    public var description: String?
    /// The credential format. The server uses `dc+sd-jwt` when it is `nil`.
    public var format: String?
    public var requestedClaims: [String]?
    public var mandatoryClaims: [String]?
    public var optionalClaims: [String]?
    public var claimValues: [String: [String]]?
    public var enforceTrustedIssuer: Bool?
    public var trustedAuthorities: [String]?

    public init(
        handle: String,
        ouId: String,
        vct: String,
        name: String? = nil,
        description: String? = nil,
        format: String? = nil,
        requestedClaims: [String]? = nil,
        mandatoryClaims: [String]? = nil,
        optionalClaims: [String]? = nil,
        claimValues: [String: [String]]? = nil,
        enforceTrustedIssuer: Bool? = nil,
        trustedAuthorities: [String]? = nil
    ) {
        self.handle = handle
        self.ouId = ouId
        self.vct = vct
        self.name = name
        self.description = description
        self.format = format
        self.requestedClaims = requestedClaims
        self.mandatoryClaims = mandatoryClaims
        self.optionalClaims = optionalClaims
        self.claimValues = claimValues
        self.enforceTrustedIssuer = enforceTrustedIssuer
        self.trustedAuthorities = trustedAuthorities
    }
}
