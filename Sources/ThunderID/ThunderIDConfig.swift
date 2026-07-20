/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import Foundation

/// Configuration for the ThunderID SDK.
public struct ThunderIDConfig {
    // MARK: - Core
    public let baseUrl: String
    public let clientId: String?

    // MARK: - Redirect URIs
    public var afterSignInUrl: String?
    public var afterSignOutUrl: String?
    public var signInUrl: String?
    public var signUpUrl: String?

    // MARK: - OAuth2 / OIDC
    public var scopes: [String]
    public var clientSecret: String?
    public var signInOptions: [String: Any]
    public var signOutOptions: [String: Any]
    public var signUpOptions: [String: Any]

    // MARK: - Application Identity
    public var applicationId: String?
    public var organizationHandle: String?

    // MARK: - Platform Attestation
    /// When enabled, the token from ``attestationTokenProvider`` is sent as the
    /// `Attestation-Token` header on native flow-initiate requests.
    public var attestationEnabled: Bool
    public var attestationTokenProvider: (() async throws -> String)?

    // MARK: - Token Validation
    public var tokenValidation: TokenValidationConfig

    // MARK: - Storage & Platform
    public var storage: StorageAdapter?
    public var instanceId: Int?

    /// Vendor/brand namespace used to derive default storage identifiers (e.g. Keychain service name).
    /// Override this when white-labeling the SDK under a different brand. Defaults to
    /// `VendorConstants.vendorPrefix` ("thunderid").
    public var vendor: String

    public init(
        baseUrl: String,
        clientId: String? = nil,
        scopes: [String] = ["openid"],
        afterSignInUrl: String? = nil,
        afterSignOutUrl: String? = nil,
        signInUrl: String? = nil,
        signUpUrl: String? = nil,
        clientSecret: String? = nil,
        signInOptions: [String: Any] = [:],
        signOutOptions: [String: Any] = [:],
        signUpOptions: [String: Any] = [:],
        applicationId: String? = nil,
        organizationHandle: String? = nil,
        attestationEnabled: Bool = false,
        attestationTokenProvider: (() async throws -> String)? = nil,
        tokenValidation: TokenValidationConfig = .init(),
        storage: StorageAdapter? = nil,
        instanceId: Int? = nil,
        vendor: String = VendorConstants.vendorPrefix
    ) {
        self.baseUrl = baseUrl
        self.clientId = clientId
        self.scopes = scopes
        self.afterSignInUrl = afterSignInUrl
        self.afterSignOutUrl = afterSignOutUrl
        self.signInUrl = signInUrl
        self.signUpUrl = signUpUrl
        self.clientSecret = clientSecret
        self.signInOptions = signInOptions
        self.signOutOptions = signOutOptions
        self.signUpOptions = signUpOptions
        self.applicationId = applicationId
        self.organizationHandle = organizationHandle
        self.attestationEnabled = attestationEnabled
        self.attestationTokenProvider = attestationTokenProvider
        self.tokenValidation = tokenValidation
        self.storage = storage
        self.instanceId = instanceId
        self.vendor = vendor
    }
}

public struct TokenValidationConfig {
    public var validate: Bool
    public var validateIssuer: Bool
    public var clockTolerance: Int

    public init(validate: Bool = true, validateIssuer: Bool = true, clockTolerance: Int = 0) {
        self.validate = validate
        self.validateIssuer = validateIssuer
        self.clockTolerance = clockTolerance
    }
}
