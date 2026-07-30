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

    /// Returns the base64-encoded App Attest attestation object, which is what the
    /// `Attestation-Token` header carries.
    ///
    /// A key can be attested only once, and the server verifies a fresh attestation object on every
    /// flow initiation, so this generates a new key per call rather than reusing a stored one.
    func requestToken() async throws -> String {
        guard service.isSupported else { throw AppAttestError.unsupported }
        let keyId = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: makeChallenge()))
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        return attestation.base64EncodedString()
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
