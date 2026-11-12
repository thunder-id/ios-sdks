// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// With `baseUrl` set to the issuer of an OpenID provider other than ThunderID, a redirect sign-in reads its
/// endpoints from the provider's metadata (`{issuer}/.well-known/openid-configuration`), and falls back to the
/// ThunderID paths under `baseUrl` when the metadata cannot be read or names none.
final class OIDCDiscoveryTests: OAuthTestCase {
    private let issuer = "https://idp.example.com/t/acme/oauth2/token"
    private let root = "https://idp.example.com/t/acme/oauth2"
    private let discovery = "/t/acme/oauth2/token/.well-known/openid-configuration"
    private let signingKey = TestSigningKey()

    private func metadata(issuer advertisedIssuer: String? = nil) -> String {
        let fields: [String: String] = [
            "issuer": advertisedIssuer ?? issuer,
            "authorization_endpoint": "\(root)/authorize",
            "token_endpoint": "\(root)/token",
            "jwks_uri": "\(root)/jwks",
            "userinfo_endpoint": "\(root)/userinfo",
            "revocation_endpoint": "\(root)/revoke"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func makeProviderClient(baseUrl: String? = nil, validate: Bool = false) async throws {
        let config = ThunderIDConfig(
            baseUrl: baseUrl ?? issuer,
            clientId: "client-1",
            scopes: ["openid", "profile"],
            afterSignInUrl: "myapp://callback",
            tokenValidation: .init(validate: validate)
        )
        client = ThunderIDClient()
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
    }

    /// A token answer whose access token carries no `sub`, so the user is read from the userinfo endpoint.
    private func tokenJSON(idToken: String? = nil, refresh: String? = nil) -> String {
        var json: [String: Any] = ["access_token": Self.jwt([:]), "token_type": "Bearer", "expires_in": 3600]
        if let idToken { json["id_token"] = idToken }
        if let refresh { json["refresh_token"] = refresh }
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func signedIn(iss: String) async throws -> User {
        StubBackend.reply("/t/acme/oauth2/jwks", signingKey.jwksJSON)
        StubBackend.reply("/t/acme/oauth2/token", tokenJSON(idToken: signingKey.idToken([
            "iss": iss,
            "sub": "u1",
            "aud": "client-1",
            "exp": Date().timeIntervalSince1970 + 300
        ])))
        StubBackend.reply("/t/acme/oauth2/userinfo", #"{"sub":"u1"}"#)
        _ = try await client.signInURL()
        return try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c1")!)
    }

    // MARK: - Endpoints from discovery

    func testTheSignInURLUsesTheDiscoveredAuthorizationEndpoint() async throws {
        try await makeProviderClient()
        StubBackend.reply(discovery, metadata())

        let url = try await client.signInURL()

        XCTAssertEqual(url.host, "idp.example.com")
        XCTAssertEqual(url.path, "/t/acme/oauth2/authorize")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "client_id" }?.value, "client-1")
        XCTAssertEqual(StubBackend.requests(to: discovery).count, 1)
        // Once the metadata is read, the synchronous builder uses it too.
        XCTAssertEqual(try client.buildSignInURL().path, "/t/acme/oauth2/authorize")
    }

    func testTheCodeIsRedeemedAndTheUserReadAtTheDiscoveredEndpoints() async throws {
        try await makeProviderClient()
        StubBackend.reply(discovery, metadata())
        StubBackend.reply("/t/acme/oauth2/token", tokenJSON(refresh: "r1"))
        StubBackend.reply("/t/acme/oauth2/userinfo", #"{"sub":"u1"}"#)
        _ = try await client.signInURL()

        let user = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c1")!)

        XCTAssertEqual(user.sub, "u1")
        let token = StubBackend.requests(to: "/t/acme/oauth2/token").first
        XCTAssertEqual(form(token)["grant_type"], "authorization_code")
        XCTAssertEqual(form(token)["code"], "c1")
        XCTAssertEqual(StubBackend.requests(to: "/t/acme/oauth2/userinfo").count, 1)
        XCTAssertTrue(StubBackend.requests(to: "/t/acme/oauth2/token/oauth2/token").isEmpty)
    }

    func testRefreshAndRevocationUseTheDiscoveredEndpoints() async throws {
        try await makeProviderClient()
        StubBackend.reply(discovery, metadata())
        try store.save(TokenResponse(
            accessToken: Self.jwt(["sub": "u1"]),
            tokenType: "Bearer",
            expiresIn: 0,
            refreshToken: "r1"
        ))
        StubBackend.reply("/t/acme/oauth2/token", tokenJSON(refresh: "r2"))
        StubBackend.reply("/t/acme/oauth2/revoke", "")

        _ = try await client.getAccessToken()
        _ = try await client.signOut()

        let refresh = StubBackend.requests(to: "/t/acme/oauth2/token").first
        XCTAssertEqual(form(refresh)["grant_type"], "refresh_token")
        XCTAssertEqual(form(refresh)["refresh_token"], "r1")
        XCTAssertEqual(form(StubBackend.requests(to: "/t/acme/oauth2/revoke").first)["token"], "r2")
    }

    // MARK: - Fallbacks

    func testEndpointsFallBackToTheThunderIDPathsWhenDiscoveryFails() async throws {
        try await makeProviderClient()
        StubBackend.reply(discovery, status: 404, "")
        StubBackend.reply("/t/acme/oauth2/token/oauth2/token", tokenJSON(refresh: "r1"))
        StubBackend.reply("/t/acme/oauth2/token/oauth2/userinfo", #"{"sub":"u1"}"#)

        let url = try await client.signInURL()
        _ = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c1")!)

        XCTAssertEqual(url.path, "/t/acme/oauth2/token/oauth2/authorize")
        XCTAssertEqual(StubBackend.requests(to: "/t/acme/oauth2/token/oauth2/token").count, 1)
        XCTAssertEqual(StubBackend.requests(to: "/t/acme/oauth2/token/oauth2/userinfo").count, 1)
    }

    func testAFieldTheMetadataOmitsFallsBack() async throws {
        try await makeProviderClient()
        StubBackend.reply(discovery, #"{"issuer":"\#(issuer)","token_endpoint":"\#(root)/token"}"#)

        let url = try await client.signInURL()

        XCTAssertEqual(url.path, "/t/acme/oauth2/token/oauth2/authorize")
    }

    func testTheBuilderFallsBackBeforeTheMetadataIsRead() async throws {
        try await makeProviderClient()
        StubBackend.reply(discovery, metadata())

        XCTAssertEqual(try client.buildSignInURL().path, "/t/acme/oauth2/token/oauth2/authorize")
        XCTAssertTrue(StubBackend.requests(to: discovery).isEmpty)
    }

    func testAnOrganizationUnitSignInKeepsTheThunderIDPath() async throws {
        try await makeClient()
        StubBackend.reply("/.well-known/openid-configuration", #"{"authorization_endpoint":"\#(base)/oauth2/authorize"}"#)

        let url = try await client.signInURL(options: SignInOptions(organizationUnitId: "ou-1"))

        XCTAssertEqual(url.path, "/ou/ou-1/oauth2/authorize")
    }

    // MARK: - Issuer

    func testAnIDTokenNamingTheDiscoveredIssuerWithATrailingSlashIsAccepted() async throws {
        try await makeProviderClient(validate: true)
        StubBackend.reply(discovery, metadata(issuer: issuer + "/"))

        let user = try await signedIn(iss: issuer + "/")

        XCTAssertEqual(user.sub, "u1")
        XCTAssertEqual(StubBackend.requests(to: "/t/acme/oauth2/jwks").count, 1)
    }

    func testAnIDTokenNamingTheBaseUrlIsAcceptedWithoutDiscovery() async throws {
        try await makeProviderClient(validate: true)
        StubBackend.reply(discovery, status: 404, "")
        StubBackend.reply("/t/acme/oauth2/token/oauth2/jwks", signingKey.jwksJSON)
        StubBackend.reply("/t/acme/oauth2/token/oauth2/token", tokenJSON(idToken: signingKey.idToken([
            "iss": issuer,
            "sub": "u1",
            "aud": "client-1",
            "exp": Date().timeIntervalSince1970 + 300
        ])))
        StubBackend.reply("/t/acme/oauth2/token/oauth2/userinfo", #"{"sub":"u1"}"#)
        _ = try client.buildSignInURL()

        let user = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=c1")!)

        XCTAssertEqual(user.sub, "u1")
    }

    func testAnIssuerThatIsNotTheBaseUrlIsNotTrusted() async throws {
        try await makeProviderClient(validate: true)
        StubBackend.reply(discovery, metadata(issuer: "https://other.example.com"))

        await assertThrows(.authenticationFailed) { _ = try await self.signedIn(iss: "https://other.example.com") }
        XCTAssertTrue(StubBackend.requests(to: "/t/acme/oauth2/jwks").isEmpty)
    }

    func testTheTrailingSlashMustMatchTheDiscoveredIssuer() async throws {
        try await makeProviderClient(validate: true)
        StubBackend.reply(discovery, metadata(issuer: issuer + "/"))

        await assertThrows(.authenticationFailed) { _ = try await self.signedIn(iss: self.issuer) }
    }
}

/// An RSA key that signs ID tokens as a provider would, and publishes itself as a JWKS.
struct TestSigningKey {
    let privateKey: SecKey

    init() {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
    }

    var jwksJSON: String {
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        let der = [UInt8](SecKeyCopyExternalRepresentation(publicKey, nil)! as Data)
        // PKCS #1 RSAPublicKey: SEQUENCE { INTEGER modulus, INTEGER exponent }.
        var offset = 0
        func readLength() -> Int {
            let first = Int(der[offset]); offset += 1
            guard first & 0x80 != 0 else { return first }
            var length = 0
            for _ in 0..<(first & 0x7f) { length = length << 8 | Int(der[offset]); offset += 1 }
            return length
        }
        func readInteger() -> Data {
            offset += 1
            let length = readLength()
            var bytes = Array(der[offset..<offset + length]); offset += length
            while bytes.first == 0 { bytes.removeFirst() }
            return Data(bytes)
        }
        offset += 1
        _ = readLength()
        let modulus = readInteger()
        let exponent = readInteger()
        return #"{"keys":[{"kty":"RSA","kid":"k1","alg":"RS256","n":"\#(Self.b64url(modulus))","e":"\#(Self.b64url(exponent))"}]}"#
    }

    func idToken(_ claims: [String: Any]) -> String {
        let header = Self.b64url(Data(#"{"alg":"RS256","kid":"k1","typ":"JWT"}"#.utf8))
        let payload = Self.b64url((try? JSONSerialization.data(withJSONObject: claims)) ?? Data())
        let input = Data("\(header).\(payload)".utf8)
        let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            input as CFData,
            nil
        )! as Data
        return "\(header).\(payload).\(Self.b64url(signature))"
    }

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
