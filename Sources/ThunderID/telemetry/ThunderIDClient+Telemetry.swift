// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Telemetry operations

public extension ThunderIDClient {
    /// Reports an event the app names, for what is neither a screen view, an API call nor a link. Does
    /// nothing while telemetry is off (``ThunderIDConfig/telemetry`` has no endpoint).
    ///
    /// - Parameters:
    ///   - name: The event's name, `<type>.<action>`, such as `application.template-pick`. The configured
    ///     prefix is added.
    ///   - data: Codes about it. Never a name, an email address or anything a user typed.
    func track(_ name: String, data: [String: String] = [:]) {
        telemetryClient?.telemetry.track(name, data: data)
    }

    /// Reports a screen view from its route pattern, such as `applications/:id`, never the URL or the ids in
    /// it. `applications` is `application.list-view` and `applications/:id` is `application.detail-view`.
    /// Does nothing while telemetry is off.
    func trackPageView(_ pattern: String) {
        telemetryClient?.telemetry.page(pattern)
    }

    /// Reports a link that leaves the app as `link.open`, with its host and path only, never its query or
    /// fragment. Only `http` and `https` links are reported. Does nothing while telemetry is off.
    func trackLink(_ url: URL) {
        telemetryClient?.telemetry.link(url)
    }
}

// MARK: - Wiring

extension ThunderIDClient {
    /// Starts telemetry when the configuration has an endpoint. An endpoint that is not an HTTPS URL leaves
    /// telemetry off, without failing initialization.
    ///
    /// - Parameters:
    ///   - http: The client every API call goes through.
    ///   - backend: The backend's endpoints and transport, when sign-in runs on a backend.
    func startTelemetry(
        _ config: ThunderIDConfig,
        http: HTTPClient,
        backend: (endpoints: ResolvedBackendEndpoints, transport: BackendHttpClient)?,
        session: URLSession?
    ) {
        telemetryClient = nil
        guard let telemetryConfig = config.telemetry else { return }
        let dependencies = ClientTelemetryDependencies(
            apiBases: backend.map { [$0.endpoints.proxy] } ?? Self.telemetryApiBases(config),
            baseUrl: config.baseUrl,
            backend: backend != nil,
            vendor: config.vendor,
            claims: { [weak self] in await self?.telemetryClaims() },
            // The endpoint was approved for this configuration's `baseUrl`, so no other configuration's token
            // goes to it, such as after `reInitialize(baseUrl:)` while a send is still in progress.
            accessToken: { [weak self] in
                guard let self, (try? self.getConfiguration())?.baseUrl == config.baseUrl else { return nil }
                return try? await self.getAccessToken()
            },
            session: session
        )
        guard let client = ClientTelemetry(config: telemetryConfig, dependencies: dependencies) else { return }
        telemetryClient = client
        // Every call through the SDK's HTTP transport, the management operations' included, ends here.
        let observer = Self.telemetryObserver(client.telemetry)
        http.requestObserver = observer
        backend?.transport.http.requestObserver = observer
    }

    /// Reports a sign-in that completed, once per sign-in session, or one that failed.
    func reportingSignIn<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            let result = try await operation()
            await telemetryClient?.signedIn()
            return result
        } catch {
            if !(error is CancellationError) { telemetryClient?.signInFailed(error) }
            throw error
        }
    }

    /// Reports what an app-native flow step did to the session: a completed sign-in, or a sign-in step the
    /// server refused.
    func reportFlowStep(_ response: EmbeddedFlowResponse, isSignIn: Bool) async {
        guard let telemetryClient else { return }
        if response.flowStatus == .complete, response.assertion?.isEmpty == false {
            await telemetryClient.signedIn()
        } else if isSignIn, response.flowStatus == .error {
            let code = response.error?.code.flatMap { TelemetryApiRules.isErrorCode($0) ? $0 : nil }
            telemetryClient.telemetry.auth(.signInFailed, data: code.map { ["error_code": $0] } ?? [:])
        }
    }

    /// The signed-in user's claims: the backend session's user, or the ID token's, or the access token's.
    func telemetryClaims() async -> [String: Any]? {
        if let backend {
            guard let session = try? await backend.getSession(), session.isSignedIn else { return nil }
            return session.user?.mapValues(\.value)
        }
        let tokens = [tokenStore?.idToken(), tokenStore?.accessToken()].compactMap { $0 }
        let claims = tokens.lazy.compactMap { try? self.decodeJwtToken($0) as [String: AnyCodable] }.first
        return claims?.mapValues(\.value)
    }

    /// The APIs watched for API events: `baseUrl`, and the host of each management collection that is
    /// configured elsewhere, as the collection URL without its last segment.
    static func telemetryApiBases(_ config: ThunderIDConfig) -> [String] {
        var bases = [config.baseUrl]
        for child in Mirror(reflecting: config.endpoints).children where child.label != "wellKnown" {
            guard let value = child.value as? String,
                  var components = URLComponents(string: value), components.host != nil else {
                continue
            }
            var segments = components.percentEncodedPath.split(separator: "/")
            guard !segments.isEmpty else { continue }
            segments.removeLast()
            components.percentEncodedPath = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
            components.query = nil
            if let base = components.string, !bases.contains(base) { bases.append(base) }
        }
        return bases
    }

    /// Hands each finished request to the telemetry. Reads are left out before anything else is done. Only
    /// the API's own name for the call is read from the response headers, and the body only for the error code
    /// of a failure.
    static func telemetryObserver(_ telemetry: Telemetry) -> HTTPRequestObserver {
        { [weak telemetry] request, outcome in
            guard let telemetry, let method = request.httpMethod?.uppercased(),
                  !["GET", "HEAD", "OPTIONS"].contains(method) else {
                return
            }
            let result: TelemetryApiOutcome
            switch outcome {
            case let .response(response, data):
                let event = telemetryEvent(response)
                result = (200...299).contains(response.statusCode)
                    ? .success(event: event)
                    : .failure(status: response.statusCode, responseBody: data, event: event)
            case .failed:
                result = .failure(status: nil, responseBody: nil)
            }
            telemetry.api(method: method, url: request.url, body: request.httpBody, outcome: result)
        }
    }

    /// The name the API gave a call in its `X-Telemetry-Event` response header, matched in any case.
    static func telemetryEvent(_ response: HTTPURLResponse) -> String? {
        response.allHeaderFields
            .first { ($0.key as? String)?.lowercased() == Telemetry.eventHeader }
            .flatMap { $0.value as? String }
    }
}
