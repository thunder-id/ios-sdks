// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Reads and tests the permissions an access token carries. The result only decides what an
/// application shows: the server still authorizes every management request.
public enum ThunderIDPermissions {
    /// Returns the permissions in an access token's `scopes` (list) or `scope` (space-separated)
    /// claim. Returns an empty list for a missing or malformed token. The signature is not
    /// verified, so the result MUST NOT be used for an authorization decision.
    public static func fromAccessToken(_ accessToken: String?) -> [String] {
        let parts = accessToken?.split(separator: ".", omittingEmptySubsequences: false) ?? []
        guard parts.count >= 2, let data = base64URLDecode(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        if let scopes = payload["scopes"] as? [Any] {
            return scopes.compactMap { $0 as? String }
        }
        if let scope = payload["scope"] as? String {
            return scope.split(separator: " ").map(String.init)
        }
        return []
    }

    /// Whether `granted` satisfies `required` under the server's permission hierarchy: a permission
    /// covers itself and everything beneath it, so `system` satisfies `system:user:view`.
    /// An empty `required` is always satisfied.
    public static func has(_ granted: [String], _ required: String) -> Bool {
        required.isEmpty || granted.contains { $0 == required || required.hasPrefix("\($0):") }
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}
