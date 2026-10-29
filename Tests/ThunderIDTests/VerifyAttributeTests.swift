// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

@testable import ThunderID
import XCTest

/// Self user attribute verification (SDK spec, "Self user attribute verification").
final class VerifyAttributeTests: XCTestCase {
    private let baseUrl = "https://localhost:8090"
    private let step = """
    {"executionId":"exec-1","flowStatus":"INCOMPLETE","challengeToken":"ct-1",
     "data":{"additionalData":{"maskedDestination":"a***@example.com","otpLength":"6"}}}
    """

    // Only this suite's flow calls; another suite's background request can land after `reset()`.
    private var flowRequests: [StubBackend.Recorded] {
        StubBackend.requests.filter { $0.request.url?.path.hasSuffix("/flow/execute") == true }
    }

    override func setUp() {
        super.setUp()
        StubBackend.reset()
    }

    override func tearDown() {
        StubBackend.reset()
        super.tearDown()
    }

    private func makeClient(endpoints: ThunderIDEndpoints = .init()) async throws -> ThunderIDClient {
        let storage = InMemoryStorageAdapter()
        try TokenStore(storage: storage).save(
            TokenResponse(accessToken: "user-token", tokenType: "Bearer", expiresIn: 3600)
        )
        let client = ThunderIDClient()
        let config = ThunderIDConfig(
            baseUrl: baseUrl,
            clientId: "client",
            applicationId: "app-1",
            endpoints: endpoints
        )
        _ = try await client.initialize(config: config, storage: storage, session: StubBackend.makeSession())
        return client
    }

    private func assertThrows(
        _ code: ThunderIDErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Expected \(code.rawValue)", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? ThunderIDError)?.code, code, "\(error)", file: file, line: line)
        }
    }

    // MARK: - Starting

    func testStartNamesTheFlowAndAttributeWithTheAccessTokenAndNoUserOrApplicationId() async throws {
        StubBackend.reply("/flow/execute", step)
        let client = try await makeClient()

        let response = try await client.verifyAttribute("email")

        XCTAssertEqual(response.flowId, "exec-1")
        XCTAssertEqual(response.flowStatus, .promptOnly)
        XCTAssertEqual(response.data?.additionalData?["maskedDestination"]?.value as? String, "a***@example.com")
        let sent = try XCTUnwrap(flowRequests.first)
        XCTAssertEqual(flowRequests.count, 1)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.absoluteString, "\(baseUrl)/flow/execute")
        XCTAssertEqual(sent.header("Authorization"), "Bearer user-token")
        let body = try XCTUnwrap(sent.json)
        XCTAssertEqual(body["flowType"] as? String, "SELF_SERVICE")
        XCTAssertEqual(body["handle"] as? String, "default-self-attribute-verification-flow")
        XCTAssertEqual(body["inputs"] as? [String: String], ["attribute": "email"])
        XCTAssertEqual(body["verbose"] as? Bool, true)
        XCTAssertEqual(Set(body.keys), ["flowType", "handle", "inputs", "verbose"])
    }

    func testStartUsesTheNamedHandle() async throws {
        StubBackend.reply("/flow/execute", step)
        let client = try await makeClient()

        _ = try await client.verifyAttribute("mobile_number", handle: "custom-verification")

        let body = try XCTUnwrap(flowRequests.first?.json)
        XCTAssertEqual(body["handle"] as? String, "custom-verification")
        XCTAssertEqual(body["inputs"] as? [String: String], ["attribute": "mobile_number"])
    }

    func testStartWithoutAHandleFailsBeforeAnyRequest() async throws {
        let client = try await makeClient()

        await assertThrows(.invalidInput) { _ = try await client.verifyAttribute("email", handle: " ") }
        await assertThrows(.invalidInput) { _ = try await client.verifyAttribute("", handle: "h") }
        XCTAssertTrue(flowRequests.isEmpty)
    }

    func testRequiresInitialization() async {
        await assertThrows(.sdkNotInitialized) { _ = try await ThunderIDClient().verifyAttribute("email") }
        await assertThrows(.sdkNotInitialized) {
            _ = try await ThunderIDClient().verifyAttribute(payload: EmbeddedSignInPayload(flowId: "exec-1"))
        }
    }

    // MARK: - Continuing

    func testContinuationSendsTheExecutionChallengeActionAndCodeWithTheAccessToken() async throws {
        StubBackend.reply("/flow/execute", #"{"executionId":"exec-1","flowStatus":"COMPLETE"}"#)
        let client = try await makeClient()

        let response = try await client.verifyAttribute(payload: EmbeddedSignInPayload(
            flowId: "exec-1",
            actionId: "action_email_verify",
            inputs: ["otp": "123456"],
            challengeToken: "ct-1"
        ))

        XCTAssertEqual(response.flowStatus, .complete)
        let sent = try XCTUnwrap(flowRequests.first)
        XCTAssertEqual(sent.header("Authorization"), "Bearer user-token")
        let body = try XCTUnwrap(sent.json)
        XCTAssertEqual(body["executionId"] as? String, "exec-1")
        XCTAssertEqual(body["challengeToken"] as? String, "ct-1")
        XCTAssertEqual(body["action"] as? String, "action_email_verify")
        XCTAssertEqual(body["inputs"] as? [String: String], ["otp": "123456"])
        XCTAssertEqual(Set(body.keys), ["executionId", "challengeToken", "action", "inputs", "verbose"])
    }

    func testResendContinuationSendsNoInputs() async throws {
        StubBackend.reply("/flow/execute", step)
        let client = try await makeClient()

        _ = try await client.verifyAttribute(payload: EmbeddedSignInPayload(
            flowId: "exec-1",
            actionId: "action_email_resend",
            challengeToken: "ct-1"
        ))

        let body = try XCTUnwrap(flowRequests.first?.json)
        XCTAssertNil(body["inputs"])
        XCTAssertEqual(body["action"] as? String, "action_email_resend")
    }

    func testContinuationWithoutAnExecutionFailsBeforeAnyRequest() async throws {
        let client = try await makeClient()

        await assertThrows(.invalidInput) {
            _ = try await client.verifyAttribute(payload: EmbeddedSignInPayload(actionId: "a", inputs: ["otp": "1"]))
        }
        XCTAssertTrue(flowRequests.isEmpty)
    }

    // MARK: - URL

    func testEveryStepGoesToBaseUrlWhateverTheManagementOverrides() async throws {
        StubBackend.reply("/flow/execute", step)
        let client = try await makeClient(endpoints: .init(users: "https://users.example.com/users"))

        _ = try await client.verifyAttribute("email")
        _ = try await client.verifyAttribute(payload: EmbeddedSignInPayload(flowId: "exec-1"))

        XCTAssertEqual(flowRequests.map { $0.request.url?.absoluteString }, [
            "\(baseUrl)/flow/execute",
            "\(baseUrl)/flow/execute"
        ])
        XCTAssertTrue(flowRequests.allSatisfy { $0.header("Authorization") == "Bearer user-token" })
    }

    // MARK: - Refusals

    func testA4xxIsVerificationFailedWithoutTheResponseBody() async throws {
        let client = try await makeClient()
        let body = #"{"code":"FES-1017","message":"alice@example.com is not allowed","description":"secret"}"#
        let cases: [(Int, ThunderIDErrorCode)] = [
            (400, .verificationFailed), (401, .verificationFailed), (403, .verificationFailed),
            (404, .verificationFailed), (409, .verificationFailed), (429, .verificationFailed), (500, .serverError)
        ]
        for (status, code) in cases {
            StubBackend.reset()
            StubBackend.reply("/flow/execute", status: status, body)
            for call in [
                { _ = try await client.verifyAttribute("email") },
                { _ = try await client.verifyAttribute(payload: EmbeddedSignInPayload(flowId: "exec-1")) }
            ] as [() async throws -> Void] {
                do {
                    try await call()
                    XCTFail("Expected \(code.rawValue) for \(status)")
                } catch let error as ThunderIDError {
                    XCTAssertEqual(error.code, code, "status \(status)")
                    XCTAssertFalse(error.message.contains("alice"), error.message)
                    XCTAssertFalse(error.message.contains("FES-1017"), error.message)
                    XCTAssertFalse(error.message.contains("secret"), error.message)
                }
            }
        }
    }

    func testAnErrorStepIsVerificationFailedWithoutTheServerReason() async throws {
        StubBackend.reply(
            "/flow/execute",
            #"{"executionId":"exec-1","flowStatus":"ERROR","error":{"code":"FET-1112","message":"secret"}}"#
        )
        let client = try await makeClient()

        do {
            _ = try await client.verifyAttribute("email")
            XCTFail("Expected verificationFailed")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .verificationFailed)
            XCTAssertEqual(error.message, "The server refused the verification")
            XCTAssertNil(error.underlyingError)
        }
    }

    func testANetworkFailureIsANetworkError() async throws {
        let client = try await makeClient()

        await assertThrows(.networkError) { _ = try await client.verifyAttribute("email") }
    }

    // MARK: - Profile

    func testVerifiedAttributesTellAbsentFromEmpty() throws {
        func decode(_ json: String) throws -> UserProfile {
            try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
        }
        let base = #""id":"u1","attributes":{"email":"a@example.com"},"isReadOnly":false"#

        XCTAssertNil(try decode("{\(base)}").verifiedAttributes)
        XCTAssertEqual(try decode("{\(base),\"verifiedAttributes\":{}}").verifiedAttributes, [:])
        let verified = try decode("{\(base),\"verifiedAttributes\":{\"email\":{\"verifiedAt\":\"2026-10-25T10:00:00Z\"}}}")
        XCTAssertEqual(verified.verifiedAttributes?["email"], VerifiedAttribute(verifiedAt: "2026-10-25T10:00:00Z"))
    }

    // MARK: - Eligibility

    func testOnlyTopLevelSingleValuedEmailOrMobilePropertiesAreVerifiable() {
        let schema: [String: AttributeSchema] = [
            "email": AttributeSchema(type: "email"),
            "mobile_number": AttributeSchema(type: "MOBILE"),
            "given_name": AttributeSchema(type: "string"),
            "emails": AttributeSchema(type: "array"),
            "address": AttributeSchema(subAttributes: [AttributeSchema(type: "email")], type: "object")
        ]

        XCTAssertTrue(AttributeVerification.isVerifiableAttribute("email", in: schema))
        XCTAssertTrue(AttributeVerification.isVerifiableAttribute("mobile_number", in: schema))
        XCTAssertFalse(AttributeVerification.isVerifiableAttribute("given_name", in: schema))
        XCTAssertFalse(AttributeVerification.isVerifiableAttribute("emails", in: schema))
        XCTAssertFalse(AttributeVerification.isVerifiableAttribute("address", in: schema))
        XCTAssertFalse(AttributeVerification.isVerifiableAttribute("phone", in: schema))
        XCTAssertFalse(AttributeVerification.isVerifiableAttribute("email", in: nil))
    }

    func testOnlyAChangedEmailOpensVerificationAfterASave() {
        XCTAssertTrue(AttributeVerification.opensAfterSave("email"))
        XCTAssertTrue(AttributeVerification.opensAfterSave("EMAIL"))
        XCTAssertFalse(AttributeVerification.opensAfterSave("mobile"))
        XCTAssertFalse(AttributeVerification.opensAfterSave(nil))
    }

    func testSelfServiceFlowType() {
        XCTAssertEqual(FlowType.selfService.rawValue, "SELF_SERVICE")
    }
}
