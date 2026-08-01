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

/// Regression coverage for `data.additionalData` on the real Flow Execution API passkey
/// ceremony steps: `passkeyChallenge` (assertion) and `passkeyCreationOptions` (attestation) are
/// delivered as JSON-encoded strings, not nested objects.
final class PasskeyModelsTests: XCTestCase {
    func testDecodesPasskeyChallengeFromAdditionalData() throws {
        let fixture = """
        {
            "executionId": "019fb7c3-8b38-7847-8803-3492c0cb9d9b",
            "flowStatus": "INCOMPLETE",
            "challengeToken": "0ca42a78f5dc6ca6cff227948e0a161851b3aa53cfcd4a4c6d35ef7a1ea3972b",
            "data": {
                "additionalData": {
                    "passkeyChallenge": "{\\"challenge\\":\\"BL2VDRmwFr9xC194EpS_K7WI93-LmEC1wHOy_Ab1bvY\\",\\"rpId\\":\\"localhost\\"}"
                }
            }
        }
        """
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: fixture.data(using: .utf8)!)
        let challenge = response.data?.additionalData?["passkeyChallenge"]?.value as? String

        XCTAssertTrue(try XCTUnwrap(challenge).contains("\"rpId\":\"localhost\""))
        XCTAssertNil(response.data?.additionalData?["passkeyCreationOptions"])
    }

    func testDecodesPasskeyCreationOptionsFromAdditionalData() throws {
        let fixture = """
        {
            "executionId": "019fb7be-cc59-7dc0-a6d6-8e44e9c66c4b",
            "flowStatus": "INCOMPLETE",
            "challengeToken": "2304609d473e7809a89d8b9c5a1d4f8a797c5b45b915bfe0c32e0bbca2d80398",
            "data": {
                "additionalData": {
                    "passkeyCreationOptions": "{\\"challenge\\":\\"Z7Nat_G31jawazExedznHM\\",\\"rp\\":{\\"id\\":\\"localhost\\"}}"
                }
            }
        }
        """
        let response = try JSONDecoder().decode(EmbeddedFlowResponse.self, from: fixture.data(using: .utf8)!)
        let creationOptions = response.data?.additionalData?["passkeyCreationOptions"]?.value as? String

        XCTAssertTrue(try XCTUnwrap(creationOptions).contains("\"rp\":{\"id\":\"localhost\"}"))
        XCTAssertNil(response.data?.additionalData?["passkeyChallenge"])
    }
}

/// Covers the pure input-flattening helpers backing `PasskeyAuthSession`, independent of the
/// real `ASAuthorizationController` delegate glue (which requires a live authenticator to
/// exercise end-to-end).
final class PasskeyAuthSessionTests: XCTestCase {
    func testAssertionInputsIncludesUserHandleWhenPresent() {
        let inputs = PasskeyAuthSession.assertionInputs(
            credentialID: Data([0x01, 0x02]),
            rawClientDataJSON: Data([0x03]),
            rawAuthenticatorData: Data([0x04]),
            signature: Data([0x05]),
            userID: Data([0x06])
        )

        XCTAssertEqual(inputs["credentialId"], "AQI")
        XCTAssertEqual(inputs["clientDataJSON"], "Aw")
        XCTAssertEqual(inputs["authenticatorData"], "BA")
        XCTAssertEqual(inputs["signature"], "BQ")
        XCTAssertEqual(inputs["userHandle"], "Bg")
    }

    func testAssertionInputsOmitsUserHandleWhenAbsent() {
        let inputs = PasskeyAuthSession.assertionInputs(
            credentialID: Data([0x01]),
            rawClientDataJSON: Data([0x02]),
            rawAuthenticatorData: Data([0x03]),
            signature: Data([0x04]),
            userID: nil
        )

        XCTAssertNil(inputs["userHandle"])
    }

    func testAttestationInputsFlattensCredentialFields() {
        let inputs = PasskeyAuthSession.attestationInputs(
            credentialID: Data([0x01]),
            rawClientDataJSON: Data([0x02]),
            rawAttestationObject: Data([0x03])
        )

        XCTAssertEqual(
            inputs,
            ["credentialId": "AQ", "clientDataJSON": "Ag", "attestationObject": "Aw"]
        )
    }
}
