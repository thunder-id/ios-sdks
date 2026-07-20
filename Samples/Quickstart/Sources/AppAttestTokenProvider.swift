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

import CryptoKit
import DeviceCheck
import Foundation

/// Errors surfaced by ``AppAttestTokenProvider``.
enum AppAttestError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "App Attest is unavailable here — it requires a physical device with a Secure Enclave."
        }
    }
}

/// Mints Apple App Attest tokens for `ThunderIDConfig.attestationTokenProvider`.
/// Requires a physical device and the App Attest entitlement. The challenge should
/// come from the server in production; this sample generates it locally.
final class AppAttestTokenProvider {
    private let service = DCAppAttestService.shared
    private let keyIdStorageKey: String
    private let attestedStorageKey: String

    init(keyPrefix: String = "dev.thunderid.quickstart.appAttest") {
        keyIdStorageKey = "\(keyPrefix).keyId"
        attestedStorageKey = "\(keyPrefix).attested"
    }

    /// Returns a base64-encoded attestation/assertion envelope.
    func requestToken() async throws -> String {
        guard service.isSupported else { throw AppAttestError.unsupported }
        let keyId = try await resolveKeyId()
        let challenge = makeChallenge()
        let clientDataHash = Data(SHA256.hash(data: challenge))
        let envelope = try await buildEnvelope(keyId: keyId, challenge: challenge, clientDataHash: clientDataHash)
        let data = try JSONSerialization.data(withJSONObject: envelope)
        return data.base64EncodedString()
    }

    /// Returns the stored key id, generating one on first use.
    private func resolveKeyId() async throws -> String {
        if let existing = UserDefaults.standard.string(forKey: keyIdStorageKey) {
            return existing
        }
        let keyId = try await service.generateKey()
        UserDefaults.standard.set(keyId, forKey: keyIdStorageKey)
        return keyId
    }

    /// Attests the key on first use, then asserts on later calls.
    private func buildEnvelope(
        keyId: String,
        challenge: Data,
        clientDataHash: Data
    ) async throws -> [String: String] {
        var envelope: [String: String] = [
            "platform": "ios",
            "keyId": keyId,
            "challenge": challenge.base64EncodedString()
        ]
        if UserDefaults.standard.bool(forKey: attestedStorageKey) {
            let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
            envelope["type"] = "assertion"
            envelope["assertion"] = assertion.base64EncodedString()
        } else {
            let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
            UserDefaults.standard.set(true, forKey: attestedStorageKey)
            envelope["type"] = "attestation"
            envelope["attestation"] = attestation.base64EncodedString()
        }
        return envelope
    }

    /// Generates a random 32-byte challenge.
    private func makeChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            var generator = SystemRandomNumberGenerator()
            return Data((0..<bytes.count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        }
        return Data(bytes)
    }
}
