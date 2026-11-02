// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The app backend's auth endpoints, set as `endpoints.backend`. Setting them hands sign-in to a
/// backend the app owns (the Backend for Frontend pattern of RFC 10017): the backend runs the OAuth
/// flow and keeps the tokens, and API calls go through it. The app only holds an opaque session
/// handle, kept in the configured storage (the Keychain by default).
///
/// The config's `baseUrl` is then the backend's base URL. An endpoint is either a path that starts with `/`,
/// resolved against `baseUrl`, or an absolute HTTPS URL, used as is. Each defaults to a fixed path under
/// `/api/auth`. API calls go to the backend's ``proxy``, which maps them to the API from its own
/// configuration, so the app never knows the API's address: an API path such as `/users` is sent to
/// `{baseUrl}{proxy}/users`.
///
/// ```swift
/// ThunderIDConfig(
///     baseUrl: "https://app.example.com",
///     endpoints: .init(backend: .init(proxy: "/api/proxy"))
/// )
/// ```
public struct ThunderIDBackendEndpoints {
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
    /// The backend's API proxy. Every API call goes under it: the SDK's own (`/users/me` and the management
    /// API) and the app's, sent as a path such as `/users` or as a URL already under the proxy. The backend
    /// maps the proxy to the API. Defaults to `/api/auth/proxy`.
    public var proxy: String
    /// Issues the access token for ``bypass``, as an OAuth token response without a refresh token.
    /// Defaults to `/api/auth/token`.
    public var token: String
    /// Requests that skip the proxy and go straight from the app.
    public var bypass: ThunderIDBackendBypass

    public init(
        signIn: String = "/api/auth/signin",
        session: String = "/api/auth/session",
        checkSession: String = "/api/auth/checksession",
        refresh: String = "/api/auth/refresh",
        signOut: String = "/api/auth/signout",
        proxy: String = "/api/auth/proxy",
        token: String = "/api/auth/token",
        bypass: ThunderIDBackendBypass = .init()
    ) {
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

/// The backend endpoints as absolute URLs.
struct ResolvedBackendEndpoints: Equatable {
    /// The backend's base URL (the config's `baseUrl`), which relative endpoints resolve against.
    let baseUrl: String
    let signIn: URL
    let session: URL
    let checkSession: URL
    let refresh: URL
    let signOut: URL
    let proxy: String
    let token: URL
    let bypassUrls: [String]
    let attachToken: Bool

    /// Resolves `endpoints` against the backend's base URL, the config's `baseUrl`. Fails, before any network
    /// call, when the base URL or a bypass URL does not use HTTPS, or when an endpoint is neither a path that
    /// starts with `/` nor an HTTPS URL.
    static func resolve(_ endpoints: ThunderIDBackendEndpoints, baseUrl: String) throws -> Self {
        let base = trimmingTrailingSlashes(baseUrl)
        guard isHTTPS(base) else {
            throw ThunderIDError(code: .invalidConfiguration, message: "baseUrl must use HTTPS")
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

    /// The URL an API call is sent to: a URL already under the proxy as it is, a path such as `/users` under
    /// the proxy, and `nil` for any other URL, which cannot be sent with the session.
    func proxyURL(for url: URL) -> URL? {
        let target = url.absoluteString
        if Self.isUnder(target, base: proxy) { return url }
        guard url.host == nil, target.hasPrefix("/"), !target.hasPrefix("//") else { return nil }
        return URL(string: proxy + target)
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

    /// A path that starts with `/` resolves against `base`; an absolute HTTPS URL is used as is.
    private static func url(_ base: String, _ value: String, _ name: String) throws -> URL {
        if value.hasPrefix("/"), !value.hasPrefix("//"), let url = URL(string: base + value) {
            return url
        }
        if isHTTPS(value), let url = URL(string: value) {
            return url
        }
        throw ThunderIDError(
            code: .invalidConfiguration,
            message: "endpoints.backend.\(name) must be a path that starts with / or an HTTPS URL"
        )
    }

    private static func isHTTPS(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
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
    /// The scopes the access token was granted, space separated, as the token response's `scope`
    /// (RFC 6749 §5.1). The app reads its permissions from here, so the token can stay on the backend.
    let scope: String?
    let handle: String?

    static let signedOut = BackendSession(isSignedIn: false, user: nil, expiresAt: nil, scope: nil, handle: nil)
}
