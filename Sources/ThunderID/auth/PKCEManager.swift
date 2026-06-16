import Foundation
import CryptoKit

/// Generates and manages PKCE parameters per RFC 7636 (spec §11.2).
/// S256 only. code_verifier held in memory, cleared after exchange.
final class PKCEManager {
    private(set) var codeVerifier: String?

    func generate() -> (verifier: String, challenge: String) {
        let verifier = generateVerifier()
        let challenge = deriveChallenge(from: verifier)
        codeVerifier = verifier
        return (verifier, challenge)
    }

    func clearVerifier() {
        codeVerifier = nil
    }

    private func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func deriveChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
