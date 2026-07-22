/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import XCTest
@testable import ThunderID

final class ThunderIDClientTests: XCTestCase {
    var client: ThunderIDClient!

    override func setUp() {
        super.setUp()
        client = ThunderIDClient()
    }

    // MARK: - Initialization

    func testInitializeSucceeds() async throws {
        let config = ThunderIDConfig(
            baseUrl: "https://localhost:8090",
            clientId: "test-client"
        )
        let result = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        XCTAssertTrue(result)
    }

    func testInitializeRejectsHTTP() async {
        let config = ThunderIDConfig(baseUrl: "http://localhost:8090", clientId: "test")
        do {
            _ = try await client.initialize(config: config)
            XCTFail("Expected INVALID_CONFIGURATION error")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .invalidConfiguration)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInitializeThrowsWhenCalledTwice() async throws {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test")
        _ = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        do {
            _ = try await client.initialize(config: config)
            XCTFail("Expected ALREADY_INITIALIZED error")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .alreadyInitialized)
        }
    }

    func testOperationsBeforeInitThrow() async {
        do {
            _ = try await client.isSignedIn()
            XCTFail("Expected SDK_NOT_INITIALIZED")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .sdkNotInitialized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Configuration

    func testGetConfigurationReturnsConfig() async throws {
        let config = ThunderIDConfig(
            baseUrl: "https://localhost:8090",
            clientId: "test-client",
            scopes: ["openid", "profile"]
        )
        _ = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        let retrieved = try client.getConfiguration()
        XCTAssertEqual(retrieved.baseUrl, "https://localhost:8090")
        XCTAssertEqual(retrieved.clientId, "test-client")
        XCTAssertEqual(retrieved.scopes, ["openid", "profile"])
    }

    // MARK: - PKCE

    func testPKCEManagerGeneratesS256Challenge() {
        let manager = PKCEManager()
        let (verifier, challenge) = manager.generate()
        XCTAssertFalse(verifier.isEmpty)
        XCTAssertFalse(challenge.isEmpty)
        XCTAssertNotEqual(verifier, challenge)
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        // challenge must be URL-safe base64 (no +, /, =)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    func testPKCEManagerClearsVerifierAfterExplicitClear() {
        let manager = PKCEManager()
        _ = manager.generate()
        XCTAssertNotNil(manager.codeVerifier)
        manager.clearVerifier()
        XCTAssertNil(manager.codeVerifier)
    }

    // MARK: - Token Store

    func testTokenStoreSavesAndRetrieves() throws {
        let storage = InMemoryStorageAdapter()
        let store = TokenStore(storage: storage)
        let response = TokenResponse(
            accessToken: "access123",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh456",
            idToken: "id789"
        )
        try store.save(response)
        XCTAssertEqual(store.accessToken(), "access123")
        XCTAssertEqual(store.refreshToken(), "refresh456")
        XCTAssertEqual(store.idToken(), "id789")
    }

    func testTokenStoreIsNearExpiry() throws {
        let storage = InMemoryStorageAdapter()
        let store = TokenStore(storage: storage)
        let response = TokenResponse(
            accessToken: "access123",
            tokenType: "Bearer",
            expiresIn: 30  // expires in 30s — within 60s threshold
        )
        try store.save(response)
        XCTAssertTrue(store.isNearExpiry())
    }

    func testTokenStoreNotNearExpiry() throws {
        let storage = InMemoryStorageAdapter()
        let store = TokenStore(storage: storage)
        let response = TokenResponse(
            accessToken: "access123",
            tokenType: "Bearer",
            expiresIn: 3600
        )
        try store.save(response)
        XCTAssertFalse(store.isNearExpiry())
    }

    func testTokenStoreClear() throws {
        let storage = InMemoryStorageAdapter()
        let store = TokenStore(storage: storage)
        try store.save(TokenResponse(accessToken: "tok", tokenType: "Bearer"))
        store.clear()
        XCTAssertNil(store.accessToken())
    }

    // MARK: - isLoading

    func testIsLoadingDefaultsFalse() async throws {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test")
        _ = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        XCTAssertFalse(client.isLoading())
    }

    // MARK: - Sign-out clears session

    func testClearSession() async throws {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test")
        _ = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        client.clearSession()
        let isSignedIn = try await client.isSignedIn()
        XCTAssertFalse(isSignedIn)
    }

    // MARK: - JWT decode

    func testDecodeJwtToken() async throws {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", clientId: "test")
        _ = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        // Simple JWT with base64url-encoded payload {"sub":"1234","name":"Test"}
        let payload = "{\"sub\":\"1234\",\"name\":\"Test\"}"
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let fakeJwt = "eyJhbGciOiJSUzI1NiJ9.\(b64).fakesig"
        let decoded: [String: String] = try client.decodeJwtToken(fakeJwt)
        XCTAssertEqual(decoded["sub"], "1234")
        XCTAssertEqual(decoded["name"], "Test")
    }

    // MARK: - Error codes

    func testThunderIDErrorCodes() {
        let error = ThunderIDError(code: .authenticationFailed, message: "bad creds")
        XCTAssertEqual(error.code.rawValue, "AUTHENTICATION_FAILED")
        XCTAssertNotNil(error.errorDescription)
    }

    func testFlowSubmitBodyUsesActionField() {
        let http = HTTPClient(baseUrl: "https://localhost:8090")
        let flowClient = FlowExecutionClient(httpClient: http)

        let body = flowClient.submitBody(flowId: "flow-123", actionId: "basic_auth", challengeToken: nil)

        XCTAssertEqual(body["executionId"] as? String, "flow-123")
        XCTAssertEqual(body["action"] as? String, "basic_auth")
        XCTAssertNil(body["actionId"])
    }

    // MARK: - Attestation

    func testAttestationDisabledByDefault() {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090")
        XCTAssertFalse(config.attestationEnabled)
        XCTAssertNil(config.attestationTokenProvider)
    }

    func testInitializeRejectsAttestationEnabledWithoutProvider() async {
        let config = ThunderIDConfig(baseUrl: "https://localhost:8090", attestationEnabled: true)
        do {
            _ = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
            XCTFail("Expected INVALID_CONFIGURATION error")
        } catch let error as ThunderIDError {
            XCTAssertEqual(error.code, .invalidConfiguration)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInitializeAcceptsAttestationEnabledWithProvider() async throws {
        let config = ThunderIDConfig(
            baseUrl: "https://localhost:8090",
            attestationEnabled: true,
            attestationTokenProvider: { "test-token" }
        )
        let result = try await client.initialize(config: config, storage: InMemoryStorageAdapter())
        XCTAssertTrue(result)
    }
}
