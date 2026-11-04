// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// The token and revocation endpoints read only form-encoded bodies (RFC 6749 §4.1.3, RFC 7009 §2.1), so every
/// request to them is sent that way, whether or not the sign-in was bounded to an organization unit.
final class TokenRequestEncodingTests: OAuthTestCase {
    private let formType = "application/x-www-form-urlencoded"

    func testAnAuthorizationCodeIsRedeemedFormEncoded() async throws {
        try await makeClient()
        StubBackend.reply("/oauth2/token", tokenJSON(["sub": "u1"], refresh: "r2"))
        StubBackend.reply("/oauth2/userinfo", #"{"sub":"u1"}"#)
        _ = try client.buildSignInURL()

        _ = try await client.handleRedirectCallback(url: URL(string: "myapp://callback?code=the-code")!)

        let request = StubBackend.requests(to: "/oauth2/token").first
        XCTAssertEqual(request?.header("Content-Type"), formType)
        XCTAssertEqual(form(request)["grant_type"], "authorization_code")
        XCTAssertEqual(form(request)["code"], "the-code")
        XCTAssertEqual(store.refreshToken(), "r2")
    }

    func testAnExpiredAccessTokenIsRefreshedFormEncoded() async throws {
        try await makeClient()
        try store.save(TokenResponse(
            accessToken: Self.jwt(["sub": "u1"]),
            tokenType: "Bearer",
            expiresIn: 0,
            refreshToken: "r1"
        ))
        StubBackend.reply("/oauth2/token", tokenJSON(["sub": "u1"], refresh: "r2"))

        _ = try await client.getAccessToken()

        let request = StubBackend.requests(to: "/oauth2/token").first
        XCTAssertEqual(request?.header("Content-Type"), formType)
        XCTAssertEqual(form(request)["grant_type"], "refresh_token")
        XCTAssertEqual(form(request)["refresh_token"], "r1")
    }

    func testATokenExchangeIsSentFormEncoded() async throws {
        try await makeClient()
        StubBackend.reply("/oauth2/token", tokenJSON(["sub": "u1"]))

        _ = try await client.exchangeToken(config: TokenExchangeRequestConfig(subjectToken: "s", subjectTokenType: "urn:x"))

        let request = StubBackend.requests(to: "/oauth2/token").first
        XCTAssertEqual(request?.header("Content-Type"), formType)
        XCTAssertEqual(form(request)["grant_type"], "urn:ietf:params:oauth:grant-type:token-exchange")
        XCTAssertEqual(form(request)["subject_token"], "s")
    }

    func testSignOutRevokesTheRefreshTokenFormEncoded() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"], refreshToken: "r1")
        StubBackend.reply("/oauth2/revoke", "")

        _ = try await client.signOut()

        let request = StubBackend.requests(to: "/oauth2/revoke").first
        XCTAssertEqual(request?.header("Content-Type"), formType)
        XCTAssertEqual(form(request)["token"], "r1")
        XCTAssertEqual(form(request)["client_id"], "client-1")
    }
}
