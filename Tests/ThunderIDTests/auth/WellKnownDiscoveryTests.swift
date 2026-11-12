// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// With `baseUrl` set to a provider's root URL and `endpoints.wellKnown` to its discovery URL, the metadata is
/// read from `wellKnown`, and the ID token's issuer is derived from it (OpenID Connect Discovery 1.0 §4.3).
final class WellKnownDiscoveryTests: OAuthTestCase {
    private let root = "https://idp.example.com/t/acme"
    private let issuer = "https://idp.example.com/t/acme/oauth2/token"
    private let wellKnownPath = "/t/acme/oauth2/token/.well-known/openid-configuration"
    private var wellKnown: String { "https://idp.example.com" + wellKnownPath }
    private let signingKey = TestSigningKey()

    private func makeProviderClient(wellKnown: String?, validate: Bool = true) async throws {
        let config = ThunderIDConfig(
            baseUrl: root,
            clientId: "client-1",
            scopes: ["openid", "profile"],
            afterSignInUrl: "myapp://callback",
            tokenValidation: .init(validate: validate),
            endpoints: .init(wellKnown: wellKnown)
        )
        client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
    }

    /// Metadata naming `issuer`, with every endpoint under `endpointRoot`.
    private func metadata(issuer advertisedIssuer: String, endpointRoot: String) -> String {
        let fields: [String: String] = [
            "issuer": advertisedIssuer,
            "authorization_endpoint": "\(endpointRoot)/authorize",
            "token_endpoint": "\(endpointRoot)/token",
            "jwks_uri": "\(endpointRoot)/jwks",
            "userinfo_endpoint": "\(endpointRoot)/userinfo"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Signs in through the endpoints under `endpointPath`, with an ID token naming `iss`. The access token
    /// carries no `sub`, so the user is read from the userinfo endpoint.
    @discardableResult
    private func signIn(iss: String, endpointPath: String) async throws -> (URL, User) {
        let idToken = signingKey.idToken([
            "iss": iss,
            "sub": "u1",
            "aud": "client-1",
            "exp": Date().timeIntervalSince1970 + 300
        ])
        let token: [String: Any] = ["access_token": Self.jwt([:]), "token_type": "Bearer", "id_token": idToken]
        let tokenData = try JSONSerialization.data(withJSONObject: token)
        StubBackend.reply("\(endpointPath)/jwks", signingKey.jwksJSON)
        StubBackend.reply("\(endpointPath)/token", String(data: tokenData, encoding: .utf8) ?? "{}")
        StubBackend.reply("\(endpointPath)/userinfo", #"{"sub":"u1"}"#)
        let url = try await client.signInURL()
        let user = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c1")!)
        return (url, user)
    }

    func testTheSignInUsesTheEndpointsTheWellKnownDocumentAdvertises() async throws {
        try await makeProviderClient(wellKnown: wellKnown)
        StubBackend.reply(wellKnownPath, metadata(issuer: issuer, endpointRoot: "https://login.example.com/acme"))

        let (url, user) = try await signIn(iss: issuer, endpointPath: "/acme")

        XCTAssertEqual(url.host, "login.example.com")
        XCTAssertEqual(url.path, "/acme/authorize")
        XCTAssertEqual(user.sub, "u1")
        XCTAssertEqual(form(StubBackend.requests(to: "/acme/token").first)["code"], "c1")
        XCTAssertEqual(StubBackend.requests(to: "/acme/jwks").count, 1)
        XCTAssertEqual(StubBackend.requests(to: "/acme/userinfo").count, 1)
        XCTAssertEqual(StubBackend.requests(to: wellKnownPath).count, 1)
        XCTAssertTrue(StubBackend.requests(to: "/t/acme/.well-known/openid-configuration").isEmpty)
    }

    func testAnAsgardeoShapedIssuerDerivedFromWellKnownIsAccepted() async throws {
        try await makeProviderClient(wellKnown: wellKnown)
        StubBackend.reply(wellKnownPath, metadata(issuer: issuer, endpointRoot: "\(root)/oauth2"))

        let (url, user) = try await signIn(iss: issuer, endpointPath: "/t/acme/oauth2")

        XCTAssertEqual(url.path, "/t/acme/oauth2/authorize")
        XCTAssertEqual(user.sub, "u1")
    }

    func testAnIDTokenNamingTheBaseUrlIsRejected() async throws {
        try await makeProviderClient(wellKnown: wellKnown)
        StubBackend.reply(wellKnownPath, metadata(issuer: issuer, endpointRoot: "\(root)/oauth2"))

        await assertThrows(.authenticationFailed) {
            try await self.signIn(iss: self.root, endpointPath: "/t/acme/oauth2")
        }
    }

    func testTheDerivedIssuerIsExpectedWhenTheMetadataCannotBeRead() async throws {
        try await makeProviderClient(wellKnown: wellKnown)
        StubBackend.reply(wellKnownPath, status: 404, "")

        let (url, user) = try await signIn(iss: issuer, endpointPath: "/t/acme/oauth2")

        XCTAssertEqual(url.path, "/t/acme/oauth2/authorize")
        XCTAssertEqual(user.sub, "u1")
    }

    func testANonStandardWellKnownExpectsTheDiscoveredIssuer() async throws {
        try await makeProviderClient(wellKnown: "https://idp.example.com/t/acme/discovery.json")
        StubBackend.reply(
            "/t/acme/discovery.json",
            metadata(issuer: "https://issuer.example.com/acme", endpointRoot: "\(root)/oauth2")
        )

        let (_, user) = try await signIn(iss: "https://issuer.example.com/acme", endpointPath: "/t/acme/oauth2")

        XCTAssertEqual(user.sub, "u1")
    }

    func testANonStandardWellKnownRejectsAnyOtherIssuer() async throws {
        try await makeProviderClient(wellKnown: "https://idp.example.com/t/acme/discovery.json")
        StubBackend.reply(
            "/t/acme/discovery.json",
            metadata(issuer: "https://issuer.example.com/acme", endpointRoot: "\(root)/oauth2")
        )

        await assertThrows(.authenticationFailed) {
            try await self.signIn(iss: self.root, endpointPath: "/t/acme/oauth2")
        }
    }

    func testANonStandardWellKnownRefusesTheTokenWhenTheMetadataCannotBeRead() async throws {
        try await makeProviderClient(wellKnown: "https://idp.example.com/t/acme/discovery.json")
        StubBackend.reply("/t/acme/discovery.json", status: 404, "")

        await assertThrows(.authenticationFailed) {
            try await self.signIn(iss: self.root, endpointPath: "/t/acme/oauth2")
        }
    }

    func testAWellKnownThatIsNotHTTPSIsRefused() async throws {
        await assertThrows(.invalidConfiguration) {
            try await self.makeProviderClient(wellKnown: "http://idp.example.com/.well-known/openid-configuration")
        }
    }
}
