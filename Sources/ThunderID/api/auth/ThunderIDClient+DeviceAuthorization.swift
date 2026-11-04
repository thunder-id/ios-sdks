// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The device authorization endpoint's answer (RFC 8628 section 3.2). `deviceCode` is a credential: it
/// is never shown to the user, and the type's descriptions leave it out so it cannot reach a log.
public struct DeviceAuthorizationResponse: Decodable, Equatable {
    /// Polled for with ``ThunderIDClient/pollDeviceAuthorization(deviceCode:interval:)``. Never show or log it.
    public let deviceCode: String
    /// The code the user enters at the verification URI. Show it.
    public let userCode: String
    public let verificationUri: String
    /// The verification URI with the user code in it, for a link or a QR code.
    public let verificationUriComplete: String?
    /// The lifetime of both codes, in seconds.
    public let expiresIn: Int
    /// The least number of seconds between two polls.
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }

    public init(
        deviceCode: String,
        userCode: String,
        verificationUri: String,
        verificationUriComplete: String? = nil,
        expiresIn: Int,
        interval: Int = 5
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
        self.expiresIn = expiresIn
        self.interval = interval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceCode = try container.decode(String.self, forKey: .deviceCode)
        userCode = try container.decode(String.self, forKey: .userCode)
        verificationUri = try container.decode(String.self, forKey: .verificationUri)
        verificationUriComplete = try container.decodeIfPresent(String.self, forKey: .verificationUriComplete)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 600
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 5
    }
}

extension DeviceAuthorizationResponse: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "DeviceAuthorizationResponse(userCode: \(userCode), verificationUri: \(verificationUri), "
            + "expiresIn: \(expiresIn), interval: \(interval), deviceCode: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "userCode": userCode,
            "verificationUri": verificationUri,
            "verificationUriComplete": verificationUriComplete as Any,
            "expiresIn": expiresIn,
            "interval": interval,
            "deviceCode": "<redacted>"
        ])
    }
}

/// Device authorization (RFC 8628), the device side: for an input-constrained device, such as a TV, that
/// shows a code for the user to approve on another device. The SDK runs on a public client, so it sends
/// `client_id` and no secret, as for CIBA.
public extension ThunderIDClient {
    /// Posts to the device authorization endpoint (the server's `device_authorization_endpoint`, or
    /// `{baseUrl}/oauth2/device-authorize`) with the configured scopes, and returns the codes to show and
    /// poll with. `resource` binds the request to one resource server (RFC 8707).
    func startDeviceAuthorization(resource: String? = nil) async throws -> DeviceAuthorizationResponse {
        let config = try requireConfig()
        try refuseInBackendMode("startDeviceAuthorization")
        let clientId = try requirePublicClient(config, for: "device authorization")
        let advertised = try? await serverMetadata().deviceAuthorizationEndpoint
        let fallback = try oauthURL("/oauth2/device-authorize", organizationUnitId: nil, config: config)
        let endpoint = advertised ?? fallback
        var form: [(String, String)] = [("client_id", clientId), ("scope", config.scopes.joined(separator: " "))]
        if let resource { form.append(("resource", resource)) }
        do {
            return try await postForm(endpoint, form: form)
        } catch let failure as OAuthFailure {
            throw Self.mapOAuthFailure(failure)
        }
    }

    /// Polls the token endpoint with the `urn:ietf:params:oauth:grant-type:device_code` grant until the user
    /// approves or denies the device, under the same rules as ``pollCIBA(authReqId:interval:)``, and stores
    /// the tokens on approval.
    func pollDeviceAuthorization(deviceCode: String, interval: Int) async throws -> TokenResponse {
        let config = try requireConfig()
        try refuseInBackendMode("pollDeviceAuthorization")
        let clientId = try requirePublicClient(config, for: "device authorization")
        return try await pollTokenEndpoint(interval: interval, config: config, form: [
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ("device_code", deviceCode),
            ("client_id", clientId)
        ])
    }
}
