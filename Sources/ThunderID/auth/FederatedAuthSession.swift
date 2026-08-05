// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import AuthenticationServices
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Opens a federated/social login `redirectURL` in a system browser session and captures the
/// provider's callback URL, for the flow-execution `REDIRECTION` step (TRIGGER actions).
@MainActor
public final class FederatedAuthSession: NSObject {
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: ASWebAuthenticationSession?

    /// Cancellation by the user, surfaced so callers can silently reset state.
    public struct CancelledError: Error {}

    override public init() {
        super.init()
    }

    public func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                self?.finish(callbackURL: callbackURL, error: error)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    private func finish(callbackURL: URL?, error: Error?) {
        defer { session = nil }
        guard let continuation else { return }
        self.continuation = nil
        if let callbackURL {
            continuation.resume(returning: callbackURL)
            return
        }
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            continuation.resume(throwing: CancelledError())
            return
        }
        continuation.resume(throwing: error ?? CancelledError())
    }
}

extension FederatedAuthSession: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
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
