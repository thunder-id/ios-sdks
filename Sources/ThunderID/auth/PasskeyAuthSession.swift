// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import AuthenticationServices
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Drives native WebAuthn/passkey ceremonies via `AuthenticationServices`, translating the
/// flow-execution API's `passkeyChallenge`/`passkeyCreationOptions` JSON strings into the flat
/// `credentialId`/`clientDataJSON`/`authenticatorData`/`signature`/`userHandle` (assertion) or
/// `credentialId`/`clientDataJSON`/`attestationObject` (attestation) input maps the flow expects
/// on the next `/flow/execute` submit.
@MainActor
public final class PasskeyAuthSession: NSObject {
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var controller: ASAuthorizationController?

    override public init() {
        super.init()
    }

    /// Performs a WebAuthn assertion ceremony (sign-in with an existing passkey).
    public func authenticate(requestOptionsJson: String) async throws -> [String: String] {
        guard let data = requestOptionsJson.data(using: .utf8) else {
            throw ThunderIDError(code: .passkeyFailed, message: "Invalid passkey request options")
        }
        let options = try JSONDecoder().decode(PasskeyAssertionOptions.self, from: data)
        guard let challenge = Data(base64URLEncoded: options.challenge) else {
            throw ThunderIDError(code: .passkeyFailed, message: "Invalid passkey challenge")
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.rpId ?? ""
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = (options.allowCredentials ?? []).compactMap { descriptor in
            Data(base64URLEncoded: descriptor.id).map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        return try await perform(requests: [request])
    }

    /// Performs a WebAuthn attestation ceremony (registers a new passkey).
    public func register(creationOptionsJson: String) async throws -> [String: String] {
        guard let data = creationOptionsJson.data(using: .utf8) else {
            throw ThunderIDError(code: .passkeyFailed, message: "Invalid passkey creation options")
        }
        let options = try JSONDecoder().decode(PasskeyCreationOptions.self, from: data)
        guard let challenge = Data(base64URLEncoded: options.challenge),
              let userID = Data(base64URLEncoded: options.user.id) else {
            throw ThunderIDError(code: .passkeyFailed, message: "Invalid passkey creation options")
        }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: options.relyingParty?.id ?? ""
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: options.user.name ?? options.user.id,
            userID: userID
        )
        return try await perform(requests: [request])
    }

    private func perform(requests: [ASAuthorizationRequest]) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    /// Flattens an assertion (`navigator.credentials.get()`-equivalent) result into the input
    /// map the flow-execution API expects. Kept as a pure function, separate from the
    /// `ASAuthorizationController` delegate glue, so it can be unit tested without a real
    /// authenticator.
    nonisolated static func assertionInputs(
        credentialID: Data,
        rawClientDataJSON: Data,
        rawAuthenticatorData: Data,
        signature: Data,
        userID: Data?
    ) -> [String: String] {
        var inputs = [
            "credentialId": credentialID.base64URLEncodedString(),
            "clientDataJSON": rawClientDataJSON.base64URLEncodedString(),
            "authenticatorData": rawAuthenticatorData.base64URLEncodedString(),
            "signature": signature.base64URLEncodedString()
        ]
        if let userID {
            inputs["userHandle"] = userID.base64URLEncodedString()
        }
        return inputs
    }

    /// Flattens an attestation (`navigator.credentials.create()`-equivalent) result into the
    /// input map the flow-execution API expects.
    nonisolated static func attestationInputs(
        credentialID: Data,
        rawClientDataJSON: Data,
        rawAttestationObject: Data
    ) -> [String: String] {
        [
            "credentialId": credentialID.base64URLEncodedString(),
            "clientDataJSON": rawClientDataJSON.base64URLEncodedString(),
            "attestationObject": rawAttestationObject.base64URLEncodedString()
        ]
    }
}

extension PasskeyAuthSession: ASAuthorizationControllerDelegate {
    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { self.controller = nil }
        guard let continuation else { return }
        self.continuation = nil

        switch authorization.credential {
        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            continuation.resume(returning: Self.assertionInputs(
                credentialID: assertion.credentialID,
                rawClientDataJSON: assertion.rawClientDataJSON,
                rawAuthenticatorData: assertion.rawAuthenticatorData,
                signature: assertion.signature,
                userID: assertion.userID
            ))

        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            guard let attestationObject = registration.rawAttestationObject else {
                continuation.resume(
                    throwing: ThunderIDError(code: .passkeyFailed, message: "No attestation object returned")
                )
                return
            }
            continuation.resume(returning: Self.attestationInputs(
                credentialID: registration.credentialID,
                rawClientDataJSON: registration.rawClientDataJSON,
                rawAttestationObject: attestationObject
            ))

        default:
            continuation.resume(throwing: ThunderIDError(code: .passkeyFailed, message: "Unsupported credential type"))
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { self.controller = nil }
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error.toPasskeyThunderIDError())
    }
}

extension PasskeyAuthSession: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        let windowScene = scene as? UIWindowScene
        return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

private struct PasskeyAssertionOptions: Decodable {
    let challenge: String
    let rpId: String?
    let allowCredentials: [CredentialDescriptor]?

    struct CredentialDescriptor: Decodable {
        let id: String
    }
}

private struct PasskeyCreationOptions: Decodable {
    let challenge: String
    let relyingParty: RelyingParty?
    let user: User

    enum CodingKeys: String, CodingKey {
        case challenge
        case relyingParty = "rp"
        case user
    }

    struct RelyingParty: Decodable {
        let id: String?
    }

    struct User: Decodable {
        let id: String
        let name: String?
    }
}

private extension Error {
    func toPasskeyThunderIDError() -> ThunderIDError {
        if let error = self as? ThunderIDError {
            return error
        }
        if let authError = self as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                return ThunderIDError(
                    code: .passkeyCancelled,
                    message: "Passkey ceremony was cancelled by the user",
                    underlyingError: self
                )

            case .notInteractive, .notHandled:
                return ThunderIDError(
                    code: .passkeyNoCredential,
                    message: "No passkey credential is available",
                    underlyingError: self
                )

            default:
                return ThunderIDError(
                    code: .passkeyFailed,
                    message: "Passkey ceremony failed: \(authError.code.rawValue)",
                    underlyingError: self
                )
            }
        }
        return ThunderIDError(code: .passkeyFailed, message: "Passkey ceremony failed", underlyingError: self)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        self.init(base64Encoded: base64)
    }
}
