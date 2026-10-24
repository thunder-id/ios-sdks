// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The app backend's auth endpoints, set as `endpoints.backend`. Setting them hands sign-in to a
/// backend the app owns (the Backend for Frontend pattern of RFC 10017): the backend runs the OAuth
/// flow and keeps the tokens, and API calls go through it. The app only holds an opaque session
/// handle, kept in the configured storage (the Keychain by default).
///
/// Each endpoint is a path under ``baseUrl`` and defaults to a fixed path under `/api/auth`.
///
/// ```swift
/// endpoints: .init(backend: .init(baseUrl: "https://app.example.com"))
/// ```
public struct ThunderIDBackendEndpoints {
    /// Base URL of the backend. Required, and it must use HTTPS.
    public var baseUrl: String
    /// Starts sign-in. Defaults to `/api/auth/signin`.
    public var signIn: String
    /// Starts and reports the session. Defaults to `/api/auth/session`.
    public var session: String
    /// Reports only whether the session is still live, without refreshing it or counting as activity,
    /// so the SDK can poll it. Defaults to `/api/auth/checksession`.
    public var checkSession: String
    /// Refreshes the session. Defaults to `/api/auth/refresh`.
    public var refresh: String
    /// Ends the session. Defaults to `/api/auth/signout`.
    public var signOut: String
    /// Prefix of the API proxy. Requests under the config's `baseUrl` are sent through it. Defaults to
    /// `/api/auth/proxy`.
    public var proxy: String
    /// Issues the access token for ``bypass``, as an OAuth token response without a refresh token.
    /// Defaults to `/api/auth/token`.
    public var token: String
    /// Requests that skip the proxy and go straight from the app.
    public var bypass: ThunderIDBackendBypass

    public init(
        baseUrl: String,
        signIn: String = "/api/auth/signin",
        session: String = "/api/auth/session",
        checkSession: String = "/api/auth/checksession",
        refresh: String = "/api/auth/refresh",
        signOut: String = "/api/auth/signout",
        proxy: String = "/api/auth/proxy",
        token: String = "/api/auth/token",
        bypass: ThunderIDBackendBypass = .init()
    ) {
        self.baseUrl = baseUrl
        self.signIn = signIn
        self.session = session
        self.checkSession = checkSession
        self.refresh = refresh
        self.signOut = signOut
        self.proxy = proxy
        self.token = token
        self.bypass = bypass
    }
}

/// Requests the app sends directly rather than through the proxy, such as calls to a data plane on
/// another origin. They never carry the session handle.
///
/// ```swift
/// bypass: .init(urls: ["https://dp.example.com/api"])
/// ```
public struct ThunderIDBackendBypass {
    /// Base URLs whose requests skip the proxy. A request matches its own base URL or anything under it.
    /// Each must use HTTPS.
    public var urls: [String]
    /// Attach the access token from the `token` endpoint as `Authorization: Bearer`, and get a new one and
    /// retry once on a 401. With `false`, requests go out without a token and `token` is never called.
    public var attachToken: Bool

    public init(urls: [String] = [], attachToken: Bool = true) {
        self.urls = urls
        self.attachToken = attachToken
    }
}

/// The backend endpoints as absolute URLs, with the API base whose requests go through the proxy.
struct ResolvedBackendEndpoints: Equatable {
    /// The backend's base URL, which every backend endpoint is under.
    let baseUrl: String
    let apiBaseUrl: String
    let signIn: URL
    let session: URL
    let checkSession: URL
    let refresh: URL
    let signOut: URL
    let proxy: String
    let token: URL
    let bypassUrls: [String]
    let attachToken: Bool

    /// Resolves `endpoints` against the backend base URL. Fails, before any network call, when the base
    /// URL or a bypass URL does not use HTTPS, or when an endpoint is not a path under the base URL.
    static func resolve(_ endpoints: ThunderIDBackendEndpoints, apiBaseUrl: String) throws -> Self {
        let base = trimmingTrailingSlashes(endpoints.baseUrl)
        guard URL(string: base)?.scheme == "https", URL(string: base)?.host != nil else {
            throw ThunderIDError(code: .invalidConfiguration, message: "endpoints.backend.baseUrl must use HTTPS")
        }
        let bypassUrls = try endpoints.bypass.urls.map { url in
            guard URL(string: url)?.scheme == "https" else {
                throw ThunderIDError(
                    code: .invalidConfiguration,
                    message: "Every endpoints.backend.bypass URL must use HTTPS"
                )
            }
            return trimmingTrailingSlashes(url)
        }
        return Self(
            baseUrl: base,
            apiBaseUrl: trimmingTrailingSlashes(apiBaseUrl),
            signIn: try url(base, endpoints.signIn, "signIn"),
            session: try url(base, endpoints.session, "session"),
            checkSession: try url(base, endpoints.checkSession, "checkSession"),
            refresh: try url(base, endpoints.refresh, "refresh"),
            signOut: try url(base, endpoints.signOut, "signOut"),
            proxy: trimmingTrailingSlashes(try url(base, endpoints.proxy, "proxy").absoluteString),
            token: try url(base, endpoints.token, "token"),
            bypassUrls: bypassUrls,
            attachToken: endpoints.bypass.attachToken
        )
    }

    /// Maps an API URL to its proxy URL, or returns `nil` when the URL is not under the API base and so
    /// cannot be sent with the session.
    func proxyURL(for url: URL) -> URL? {
        let target = url.absoluteString
        guard Self.isUnder(target, base: apiBaseUrl) else { return nil }
        let rest = String(target.dropFirst(apiBaseUrl.count))
        return URL(string: proxy + (rest.hasPrefix("/") ? rest : "/\(rest)"))
    }

    /// Whether a request to `url` skips the proxy and goes straight there.
    func isBypassed(_ url: URL) -> Bool {
        bypassUrls.contains { Self.isUnder(url.absoluteString, base: $0) }
    }

    /// Whether `url` is `base` itself or under it, ending at a `/` or `?` boundary, so an entry for
    /// `https://example.com` does not match `https://example.com.attacker.test`.
    private static func isUnder(_ url: String, base: String) -> Bool {
        url == base || url.hasPrefix("\(base)/") || url.hasPrefix("\(base)?")
    }

    private static func url(_ base: String, _ path: String, _ name: String) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), let url = URL(string: base + path) else {
            throw ThunderIDError(
                code: .invalidConfiguration,
                message: "endpoints.backend.\(name) must be a path under endpoints.backend.baseUrl"
            )
        }
        return url
    }

    private static func trimmingTrailingSlashes(_ value: String) -> String {
        var trimmed = value
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

/// What the backend's session endpoint reports. The handoff that starts a session also carries the
/// session `handle`.
struct BackendSession: Decodable {
    let isSignedIn: Bool
    /// The ID token's user claims, without the protocol claims.
    let user: [String: AnyCodable]?
    /// When the backend's access token expires, in seconds since the epoch.
    let expiresAt: Double?
    let handle: String?

    static let signedOut = BackendSession(isSignedIn: false, user: nil, expiresAt: nil, handle: nil)
}
