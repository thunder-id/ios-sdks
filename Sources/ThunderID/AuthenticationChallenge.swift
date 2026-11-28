// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The server's request for a more recent sign-in (RFC 9470), read from a `401` response whose
/// `WWW-Authenticate` header is `Bearer error="insufficient_user_authentication"`. Sign the user in again
/// within ``maxAge`` seconds, then retry the request. The SDK's `ChangeCredential` and `UserProfile` views do
/// both; other calls leave it to the app.
public struct AuthenticationChallenge: Equatable {
    /// The `error` value, `insufficient_user_authentication`.
    public let error: String
    /// The `error_description` value, when the server sent one.
    public let errorDescription: String?
    /// The highest acceptable age of the sign-in, in seconds, when the server sent one.
    public let maxAge: Int?

    public init(error: String, errorDescription: String? = nil, maxAge: Int? = nil) {
        self.error = error
        self.errorDescription = errorDescription
        self.maxAge = maxAge
    }

    static let insufficientUserAuthentication = "insufficient_user_authentication"
    /// The server code of the response body that carries the same request.
    static let recentAuthenticationRequiredCode = "AUTH-4011"

    /// Reads the challenge from a failed response: the `WWW-Authenticate` header first, then the body's
    /// `description.params.maxAge` for `AUTH-4011`. `nil` for any other response.
    static func from(status: Int, header: String?, serverError: ServerError?) -> AuthenticationChallenge? {
        guard status == 401 else { return nil }
        let isBodyChallenge = serverError?.code == recentAuthenticationRequiredCode
        let bodyMaxAge = isBodyChallenge ? serverError?.description?.params?["maxAge"].flatMap { Int($0) } : nil
        let params = header.flatMap(bearerParameters)
        if let params, params["error"] == insufficientUserAuthentication {
            return AuthenticationChallenge(
                error: insufficientUserAuthentication,
                errorDescription: params["error_description"],
                maxAge: params["max_age"].flatMap { Int($0) } ?? bodyMaxAge
            )
        }
        guard isBodyChallenge else { return nil }
        return AuthenticationChallenge(error: insufficientUserAuthentication, maxAge: bodyMaxAge)
    }

    /// The auth-params of the `Bearer` challenge in a `WWW-Authenticate` value (RFC 9110 section 11.6.1),
    /// with quoted values unquoted. `nil` when the value has no `Bearer` challenge.
    static func bearerParameters(_ header: String) -> [String: String]? {
        var scanner = ChallengeScanner(Array(header))
        while let token = scanner.token() {
            if token.caseInsensitiveCompare("Bearer") == .orderedSame {
                return scanner.parameters()
            }
            if !scanner.skipToken68() { _ = scanner.parameters() }
        }
        return nil
    }
}

/// Splits a `WWW-Authenticate` value into challenges and their parameters.
private struct ChallengeScanner {
    private let chars: [Character]
    private var index = 0

    init(_ chars: [Character]) { self.chars = chars }

    private var current: Character? { index < chars.count ? chars[index] : nil }

    private mutating func skip(_ set: Set<Character>) {
        while let char = current, set.contains(char) { index += 1 }
    }

    /// The next token (a scheme or a parameter name), skipping separators before it.
    mutating func token() -> String? {
        skip([" ", "\t", ","])
        let start = index
        while let char = current, !" \t,=\"".contains(char) { index += 1 }
        return index > start ? String(chars[start..<index]) : nil
    }

    /// Skips a token68 credential (`Negotiate YWJjZA==`); false, with the index unchanged, when parameters follow.
    mutating func skipToken68() -> Bool {
        let mark = index
        skip([" ", "\t"])
        let start = index
        while let char = current, char.isASCII, char.isLetter || char.isNumber || "-._~+/".contains(char) {
            index += 1
        }
        let hasValue = index > start
        skip(["="])
        skip([" ", "\t"])
        if hasValue, current == nil || current == "," { return true }
        index = mark
        return false
    }

    /// The `name=value` pairs that follow a scheme, stopping before the next scheme.
    mutating func parameters() -> [String: String] {
        var result: [String: String] = [:]
        while true {
            let mark = index
            guard let name = token() else { return result }
            skip([" ", "\t"])
            guard current == "=" else {
                index = mark
                return result
            }
            index += 1
            skip([" ", "\t"])
            result[name.lowercased()] = value()
        }
    }

    private mutating func value() -> String {
        guard current == "\"" else { return token() ?? "" }
        index += 1
        var text = ""
        while let char = current, char != "\"" {
            if char == "\\", index + 1 < chars.count { index += 1 }
            text.append(chars[index])
            index += 1
        }
        index += 1
        return text
    }
}
