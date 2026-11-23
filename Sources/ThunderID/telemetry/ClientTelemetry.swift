// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What the client gives its telemetry.
struct ClientTelemetryDependencies {
    /// The base URLs of the SDK's API, watched for API events: `baseUrl` and the management collections'
    /// hosts, or the backend's proxy when sign-in runs on a backend.
    var apiBases: [String]
    /// `baseUrl`, whose origin decides whether the app's token may go to the endpoint.
    var baseUrl: String
    /// Whether sign-in runs on a backend, which holds the tokens, so the app has none to send.
    var backend: Bool
    /// The vendor, which namespaces what the telemetry stores.
    var vendor: String
    /// The signed-in user's ID token claims, or `nil`.
    var claims: () async -> [String: Any]?
    /// The app's access token, or `nil`.
    var accessToken: () async -> String?
    /// Where the sign-in already reported is kept.
    var defaults: UserDefaults = .standard
    /// Sends the requests. A test seam.
    var session: URLSession?
    var flushInterval: TimeInterval = 5
}

/// The SDK's telemetry on Apple platforms: sends with `URLSession`, attributes events to the ID token's
/// user and organization, reports a sign-in once per sign-in session, and sends what is waiting when the
/// app moves to the background.
final class ClientTelemetry {
    /// A send that has not finished by then is given up.
    static let requestTimeout: TimeInterval = 10

    let telemetry: Telemetry
    let endpoint: URL
    private let config: TelemetryConfig
    private let dependencies: ClientTelemetryDependencies
    /// Where the last reported sign-in is kept, so a restart, a token refresh or an organization switch is
    /// not reported again.
    private let signInKey: String
    /// The sign-in reported in this process, for a session without `auth_time` or `sid`.
    private var signInThisRun: String?
    private var backgroundObserver: NSObjectProtocol?

    /// Returns `nil`, leaving telemetry off, when there is no endpoint or it is not an HTTPS URL.
    init?(config: TelemetryConfig, dependencies: ClientTelemetryDependencies) {
        guard Telemetry.isEnabled(config),
              let url = URL(string: config.endpoint.trimmingCharacters(in: .whitespaces)),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            return nil
        }
        endpoint = url
        self.config = config
        self.dependencies = dependencies
        signInKey = "\(dependencies.vendor)-telemetry-sign-in"
        let session = dependencies.session ?? Self.makeSession()
        let tokenRule = Self.tokenRule(config: config, endpoint: url, dependencies: dependencies)
        let identityConfig = config.identity
        let claims = dependencies.claims
        let core = TelemetryDependencies(
            apiBases: dependencies.apiBases,
            identity: { Self.identity(await claims(), config: identityConfig) },
            send: { body in try await Self.send(body, to: url, token: await tokenRule(), session: session) },
            flushInterval: dependencies.flushInterval
        )
        telemetry = Telemetry(config: config, dependencies: core)
        observeBackground()
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    // MARK: - Auth events

    /// Reports a sign-in once per sign-in session, keyed by the user and the ID token's `auth_time` or
    /// `sid`: a restored session, a token refresh and an organization switch are not new sign-ins.
    func signedIn() async {
        guard let claims = await dependencies.claims(),
              let user = Self.string(claims[config.identity.userClaim]) else {
            return
        }
        let session = Self.string(claims["auth_time"]) ?? Self.string(claims["sid"])
        let key = "\(user):\(session ?? "")"
        if session == nil {
            guard signInThisRun != key else { return }
            signInThisRun = key
        } else {
            guard dependencies.defaults.string(forKey: signInKey) != key else { return }
            dependencies.defaults.set(key, forKey: signInKey)
        }
        telemetry.auth(.signIn)
    }

    /// Reports a sign-in that failed, with its error code only.
    func signInFailed(_ error: Error) {
        var data: [String: String] = [:]
        if let sdkError = error as? ThunderIDError {
            if let code = sdkError.serverError?.code, TelemetryApiRules.isErrorCode(code) {
                data["error_code"] = code
            } else {
                data["error_code"] = sdkError.code.rawValue
            }
        }
        telemetry.auth(.signInFailed, data: data)
    }

    /// Reports a sign-out and sends it, before the session it names is cleared. Waits a short time at most.
    func signedOut() async {
        let identity = Self.identity(await dependencies.claims(), config: config.identity)
        forgetSignIn()
        telemetry.auth(.signOut, identity: identity)
        await telemetry.flush(waitingAtMost: 2)
    }

    /// Reports a session that ended without the app signing out.
    func sessionExpired() {
        forgetSignIn()
        telemetry.auth(.sessionExpired)
    }

    private func forgetSignIn() {
        signInThisRun = nil
        dependencies.defaults.removeObject(forKey: signInKey)
    }

    // MARK: - Sending

    /// The token the endpoint gets: a configured token only; none when `token` is disabled or sign-in runs
    /// on a backend; the app's own token for an endpoint that shares the origin of `baseUrl`; else none.
    static func tokenRule(
        config: TelemetryConfig,
        endpoint: URL,
        dependencies: ClientTelemetryDependencies
    ) -> () async -> String? {
        switch config.token {
        case .fixed(let value):
            return { value.isEmpty ? nil : value }
        case .disabled:
            return { nil }
        case .app:
            let endpointOrigin = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)
                .flatMap(TelemetryApiRules.origin)
            let baseOrigin = URLComponents(string: dependencies.baseUrl).flatMap(TelemetryApiRules.origin)
            guard !dependencies.backend, let endpointOrigin, endpointOrigin == baseOrigin else { return { nil } }
            return dependencies.accessToken
        }
    }

    private static func send(_ body: Data, to url: URL, token: String?, session: URLSession) async throws {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        _ = try await session.data(for: request)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    // MARK: - Identity

    static func identity(_ claims: [String: Any]?, config: TelemetryIdentityConfig) -> TelemetryIdentity {
        TelemetryIdentity(
            userId: string(claims?[config.userClaim]),
            organizationId: string(claims?[config.organizationClaim])
        )
    }

    /// A claim as text: a string, or a number such as `auth_time`.
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text.isEmpty ? nil : text
        case let number as Int: return String(number)
        case let number as Double: return String(Int64(number))
        default: return nil
        }
    }

    // MARK: - Background

    private func observeBackground() {
        guard let name = Self.backgroundNotification else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let telemetry = self?.telemetry else { return }
            Task { await telemetry.flush(background: true) }
        }
    }

    private static var backgroundNotification: Notification.Name? {
        #if canImport(UIKit)
        return UIApplication.didEnterBackgroundNotification
        #elseif canImport(AppKit)
        return NSApplication.didResignActiveNotification
        #else
        return nil
        #endif
    }
}
