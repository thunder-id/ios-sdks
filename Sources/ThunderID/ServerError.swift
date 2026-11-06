// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The error envelope the ThunderID server returns with a failed request. A failed response carries it
/// as ``ThunderIDError/serverError``. An OAuth error (`{"error", "error_description"}`), as the dynamic
/// client registration endpoints return, is read into it too: `error` as the `code` and
/// `error_description` as the `message`.
public struct ServerError: Decodable, Equatable {
    /// The server's error code, such as `USR-1027`.
    public let code: String
    public let message: ServerErrorMessage?
    public let description: ServerErrorMessage?

    public init(code: String, message: ServerErrorMessage? = nil, description: ServerErrorMessage? = nil) {
        self.code = code
        self.message = message
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, description
    }

    /// Reads leniently: a message or description that is neither an object nor a string is dropped
    /// rather than failing the whole envelope.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try? container.decodeIfPresent(ServerErrorMessage.self, forKey: .message)
        description = try? container.decodeIfPresent(ServerErrorMessage.self, forKey: .description)
    }

    /// Reads the envelope from a raw response body, or returns `nil` when the body is not one.
    static func parse(_ data: Data) -> ServerError? {
        guard !data.isEmpty else { return nil }
        if let envelope = try? JSONDecoder().decode(ServerError.self, from: data) {
            return envelope
        }
        guard let oauth = try? JSONDecoder().decode(OAuthErrorBody.self, from: data) else { return nil }
        return ServerError(
            code: oauth.error,
            message: oauth.errorDescription.map { ServerErrorMessage(defaultValue: $0) }
        )
    }
}

/// The OAuth 2.0 error body (RFC 6749 section 5.2).
private struct OAuthErrorBody: Decodable {
    let error: String
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// One localizable message of a ``ServerError``: the untranslated text, its translation key, and the
/// values for the key's placeholders. The server may also send a plain string, read as `defaultValue`.
public struct ServerErrorMessage: Decodable, Equatable {
    public let key: String?
    public let defaultValue: String?
    public let params: [String: String]?

    public init(key: String? = nil, defaultValue: String? = nil, params: [String: String]? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case key, defaultValue, params
    }

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(defaultValue: text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try? container.decodeIfPresent(String.self, forKey: .key),
            defaultValue: try? container.decodeIfPresent(String.self, forKey: .defaultValue),
            params: try? container.decodeIfPresent([String: String].self, forKey: .params)
        )
    }
}
