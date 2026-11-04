// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Generates the client and flow secrets the regeneration operations save.
enum SecretGenerator {
    /// A random secret: 32 bytes from the platform's cryptographically secure generator, encoded as
    /// base64url without padding.
    static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ThunderIDError(code: .unknownError, message: "Could not generate a random secret")
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The OAuth grant types that let an agent act on behalf of a signed-in user: authorization code, CIBA
/// and token exchange. An agent holding any of them is delegated, the rule the server applies when it
/// checks an agent's grants.
public enum DelegationGrantTypes {
    public static let all: [String] = [
        "authorization_code",
        "urn:openid:params:grant-type:ciba",
        "urn:ietf:params:oauth:grant-type:token-exchange"
    ]

    /// Whether an agent acts on behalf of a signed-in user, read from the grant types of its OAuth
    /// client. The server does not store the flag, so a full agent update has to send it for the agent
    /// to stay held to the delegated grant rules.
    public static func isDelegated(_ inboundAuthConfig: [AgentInboundAuthConfig]?) -> Bool {
        let grantTypes = inboundAuthConfig?.first { $0.type == "oauth2" }?.config?.grantTypes ?? []
        return grantTypes.contains { all.contains($0) }
    }
}
