// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// `updateUserCredentials` sends `{name, currentValue?, newValue}`, validates before the network, and
/// surfaces the server's codes and its request for a more recent sign-in.
final class UpdateUserCredentialsTests: OAuthTestCase {
    private let path = "/users/me/update-credentials"

    private func signedInClient() async throws {
        try await makeClient()
        try storeSession(["sub": "u1"])
    }

    // MARK: - Request body

    func testSendsNameCurrentValueAndNewValue() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 204, "")

        try await client.updateUserCredentials(attribute: "password", currentValue: "0ld", newValue: "n3w")

        let request = try XCTUnwrap(StubBackend.requests(to: path).first)
        XCTAssertEqual(request.request.httpMethod, "POST")
        let json = try XCTUnwrap(request.json)
        XCTAssertEqual(json as NSDictionary, ["name": "password", "currentValue": "0ld", "newValue": "n3w"])
        XCTAssertNil(json["attributes"])
    }

    func testLeavesOutAnEmptyOrMissingCurrentValue() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 204, "")

        try await client.updateUserCredentials(attribute: "pin", currentValue: "", newValue: "1234")
        try await client.updateUserCredentials(newValue: "n3w")

        let bodies = StubBackend.requests(to: path).compactMap(\.json)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0] as NSDictionary, ["name": "pin", "newValue": "1234"])
        XCTAssertEqual(bodies[1] as NSDictionary, ["name": "password", "newValue": "n3w"])
    }

    // MARK: - Input validation

    func testRejectsABlankNameOrNewValueBeforeAnyRequest() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 204, "")

        await assertThrows(.invalidInput) { try await self.client.updateUserCredentials(attribute: " ", newValue: "n3w") }
        await assertThrows(.invalidInput) { try await self.client.updateUserCredentials(newValue: "") }
        await assertThrows(.invalidInput) {
            try await self.client.updateUserCredentials(currentValue: "0ld", newValue: "")
        }

        XCTAssertTrue(StubBackend.requests.isEmpty)
    }

    // MARK: - Server errors

    func testAMissingCurrentValueCarriesTheServerCodeAndMessage() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 400, """
        {"code":"USR-1047",
         "message":{"key":"error.userservice.current_credential_required","defaultValue":"Current credential required"},
         "description":{"defaultValue":"Give the credential's current value to change it"}}
        """)

        let error = await assertThrowsThunderIDError(.invalidInput) {
            try await self.client.updateUserCredentials(newValue: "n3w")
        }

        XCTAssertEqual(error?.serverError?.code, "USR-1047")
        XCTAssertEqual(error?.message, "Current credential required")
        XCTAssertNil(error?.authenticationChallenge)
    }

    func testAWrongCurrentValueCarriesTheServerCode() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 403, """
        {"code":"USR-1048","message":{"defaultValue":"Invalid current credential"}}
        """)

        let error = await assertThrowsThunderIDError(.forbidden) {
            try await self.client.updateUserCredentials(currentValue: "wrong", newValue: "n3w")
        }

        XCTAssertEqual(error?.serverError?.code, "USR-1048")
        XCTAssertEqual(error?.message, "Invalid current credential")
    }

    func testTheMessageFallsBackToTheDescription() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 403, #"{"code":"USR-1046","description":{"defaultValue":"Not allowed"}}"#)

        let error = await assertThrowsThunderIDError(.forbidden) {
            try await self.client.updateUserCredentials(newValue: "n3w")
        }

        XCTAssertEqual(error?.message, "Not allowed")
    }

    // MARK: - Authentication challenge

    private let recentAuthenticationBody = """
    {"code":"AUTH-4011",
     "message":{"key":"error.security.recent_authentication_required","defaultValue":"Recent authentication required"},
     "description":{"defaultValue":"Authenticate again","params":{"maxAge":"300"}}}
    """

    func testReadsTheChallengeFromTheHeader() async throws {
        try await signedInClient()
        let header = #"Bearer error="insufficient_user_authentication", "#
            + #"error_description="A more recent authentication is required", max_age="120""#
        StubBackend.reply(path, status: 401, recentAuthenticationBody, headers: ["WWW-Authenticate": header])

        let error = await assertThrowsThunderIDError(.stepUpRequired) {
            try await self.client.updateUserCredentials(newValue: "n3w")
        }

        XCTAssertEqual(error?.serverError?.code, "AUTH-4011")
        XCTAssertEqual(error?.message, "Recent authentication required")
        XCTAssertEqual(error?.authenticationChallenge, AuthenticationChallenge(
            error: "insufficient_user_authentication",
            errorDescription: "A more recent authentication is required",
            maxAge: 120
        ))
    }

    func testFallsBackToTheBodyWhenTheHeaderIsMissing() async throws {
        try await signedInClient()
        StubBackend.reply(path, status: 401, recentAuthenticationBody)

        let error = await assertThrowsThunderIDError(.stepUpRequired) {
            try await self.client.updateUserCredentials(newValue: "n3w")
        }

        XCTAssertEqual(error?.authenticationChallenge?.error, "insufficient_user_authentication")
        XCTAssertNil(error?.authenticationChallenge?.errorDescription)
        XCTAssertEqual(error?.authenticationChallenge?.maxAge, 300)
    }

    func testAnUnauthorizedResponseWithoutTheChallengeHasNone() async throws {
        try await signedInClient()
        StubBackend.reply(
            path,
            status: 401,
            #"{"code":"AUTH-4010","message":{"defaultValue":"Unauthorized"}}"#,
            headers: ["WWW-Authenticate": #"Bearer error="invalid_token""#]
        )

        let error = await assertThrowsThunderIDError(.authenticationFailed) {
            try await self.client.updateUserCredentials(newValue: "n3w")
        }

        XCTAssertNil(error?.authenticationChallenge)
    }

    func testParsesBearerParameters() {
        let header = #"DPoP algs="ES256", Bearer realm="x", error="insufficient_user_authentication","#
            + #" error_description="Sign in \"again\", please", max_age=60"#
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(header), [
            "realm": "x",
            "error": "insufficient_user_authentication",
            "error_description": #"Sign in "again", please"#,
            "max_age": "60"
        ])
        XCTAssertNil(AuthenticationChallenge.bearerParameters(#"Basic realm="x""#))
    }

    func testFindsBearerAfterAToken68Challenge() {
        let header = #"Negotiate YWJjZA==, Bearer error="insufficient_user_authentication", max_age="120""#
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(header), [
            "error": "insufficient_user_authentication",
            "max_age": "120"
        ])
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(#"Negotiate YWJjZA== , Bearer error="x""#), ["error": "x"])
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(#"Negotiate, Bearer error="x""#), ["error": "x"])
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(#"Bearer error="x", Negotiate YWJjZA=="#), ["error": "x"])
    }

    func testFindsBearerAfterParameterChallenges() {
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(#"Basic realm="users", Bearer error="x""#), ["error": "x"])
        XCTAssertEqual(AuthenticationChallenge.bearerParameters(#"Basic realm=x, Bearer error="x""#), ["error": "x"])
    }

    func testTheHeaderAloneIsEnoughWithoutTheBodyCode() {
        let challenge = AuthenticationChallenge.from(
            status: 401,
            header: #"Bearer error="insufficient_user_authentication""#,
            serverError: nil
        )
        XCTAssertEqual(challenge, AuthenticationChallenge(error: "insufficient_user_authentication"))
        XCTAssertNil(AuthenticationChallenge.from(
            status: 403,
            header: #"Bearer error="insufficient_user_authentication""#,
            serverError: ServerError(code: "AUTH-4011")
        ))
    }
}
