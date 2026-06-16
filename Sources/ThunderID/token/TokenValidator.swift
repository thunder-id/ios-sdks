import Foundation
import CryptoKit

/// Validates ID tokens per spec §11.4: signature (JWKS), iss, aud, exp, nonce.
final class TokenValidator {
    private let jwksCache: JWKSCache
    private let config: ThunderIDConfig

    init(jwksCache: JWKSCache, config: ThunderIDConfig) {
        self.jwksCache = jwksCache
        self.config = config
    }

    func validate(idToken: String, nonce: String?) async throws {
        guard config.tokenValidation.validate else { return }

        let parts = idToken.split(separator: ".").map(String.init)
        guard parts.count == 3 else {
            throw IAMError(code: .authenticationFailed, message: "Malformed ID token")
        }

        let payload = try decodePayload(parts[1])

        if config.tokenValidation.validateIssuer {
            guard let iss = payload["iss"] as? String, iss == config.baseUrl else {
                throw IAMError(code: .authenticationFailed, message: "ID token iss mismatch")
            }
        }

        if let clientId = config.clientId {
            let aud = payload["aud"]
            let audValid: Bool
            if let audString = aud as? String {
                audValid = audString == clientId
            } else if let audArray = aud as? [String] {
                audValid = audArray.contains(clientId)
            } else {
                audValid = false
            }
            guard audValid else {
                throw IAMError(code: .authenticationFailed, message: "ID token aud mismatch")
            }
        }

        if let exp = payload["exp"] as? TimeInterval {
            let tolerance = TimeInterval(config.tokenValidation.clockTolerance)
            guard Date().timeIntervalSince1970 <= exp + tolerance else {
                throw IAMError(code: .sessionExpired, message: "ID token has expired")
            }
        }

        if let expectedNonce = nonce, let tokenNonce = payload["nonce"] as? String {
            guard tokenNonce == expectedNonce else {
                throw IAMError(code: .authenticationFailed, message: "ID token nonce mismatch")
            }
        }

        try await verifySignature(token: idToken, parts: parts)
    }

    private func verifySignature(token: String, parts: [String]) async throws {
        var keys = try await jwksCache.getKeys()
        let verified = tryVerify(headerB64: parts[0], payloadB64: parts[1], signatureB64: parts[2], keys: keys)
        if !verified {
            keys = try await jwksCache.getKeys(forceRefresh: true)
            guard tryVerify(headerB64: parts[0], payloadB64: parts[1], signatureB64: parts[2], keys: keys) else {
                throw IAMError(code: .authenticationFailed, message: "ID token signature verification failed")
            }
        }
    }

    private func tryVerify(headerB64: String, payloadB64: String, signatureB64: String, keys: [JWK]) -> Bool {
        guard let header = try? decodeHeader(headerB64),
              let alg = header["alg"] as? String,
              alg.hasPrefix("RS") || alg.hasPrefix("ES") else {
            return false
        }

        let kid = header["kid"] as? String
        let matchingKeys = kid != nil ? keys.filter { $0.kid == kid } : keys
        let signingInput = "\(headerB64).\(payloadB64)"

        guard let signingData = signingInput.data(using: .utf8),
              let sigData = Data(base64URLEncoded: signatureB64) else {
            return false
        }

        for key in matchingKeys {
            if verifyRSA(signingData: signingData, signature: sigData, jwk: key) {
                return true
            }
        }
        return false
    }

    private func verifyRSA(signingData: Data, signature: Data, jwk: JWK) -> Bool {
        guard let nB64 = jwk.modulus, let eB64 = jwk.exponent,
              let nData = Data(base64URLEncoded: nB64),
              let eData = Data(base64URLEncoded: eB64) else {
            return false
        }

        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        var rsaKeyData = Data()
        rsaKeyData.append(contentsOf: derEncodeRSAPublicKey(modulus: nData, exponent: eData))

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(rsaKeyData as CFData, keyAttributes as CFDictionary, &error) else {
            return false
        }

        let digest = SHA256.hash(data: signingData)
        let digestData = Data(digest)

        return SecKeyVerifySignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingData as CFData,
            signature as CFData,
            &error
        )
    }

    private func derEncodeRSAPublicKey(modulus: Data, exponent: Data) -> [UInt8] {
        func encodeLength(_ length: Int) -> [UInt8] {
            if length < 0x80 { return [UInt8(length)] }
            var len = length
            var bytes: [UInt8] = []
            while len > 0 { bytes.insert(UInt8(len & 0xff), at: 0); len >>= 8 }
            return [UInt8(0x80 | bytes.count)] + bytes
        }
        func encodeInteger(_ data: Data) -> [UInt8] {
            var bytes = [UInt8](data)
            if bytes.first ?? 0 >= 0x80 { bytes.insert(0, at: 0) }
            return [0x02] + encodeLength(bytes.count) + bytes
        }
        let nEncoded = encodeInteger(modulus)
        let eEncoded = encodeInteger(exponent)
        let inner = nEncoded + eEncoded
        let seq = [UInt8(0x30)] + encodeLength(inner.count) + inner
        let algoId: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00
        ]
        let bitString = [UInt8(0x03)] + encodeLength(seq.count + 1) + [0x00] + seq
        return [0x30] + encodeLength((algoId + bitString).count) + algoId + bitString
    }

    private func decodePayload(_ base64url: String) throws -> [String: Any] {
        guard let data = Data(base64URLEncoded: base64url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IAMError(code: .authenticationFailed, message: "Failed to decode token payload")
        }
        return json
    }

    private func decodeHeader(_ base64url: String) throws -> [String: Any] {
        guard let data = Data(base64URLEncoded: base64url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IAMError(code: .authenticationFailed, message: "Failed to decode token header")
        }
        return json
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        self.init(base64Encoded: base64)
    }
}
