// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

extension ThunderIDState {
    /// Runs `operation`. When the server asks for a more recent sign-in (``ThunderIDErrorCode/stepUpRequired``),
    /// calls `onReauthenticationRequired` and rethrows when the app set it; otherwise signs the same user in
    /// again and runs `operation` once more. When that sign-in fails, is cancelled or returns another user,
    /// it throws the step-up error with the cause as `underlyingError`.
    func performWithStepUp<T>(
        onReauthenticationRequired: ((Int?) -> Void)?,
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let stepUp as ThunderIDError where stepUp.code == .stepUpRequired {
            let maxAge = stepUp.authenticationChallenge?.maxAge
            if let onReauthenticationRequired {
                onReauthenticationRequired(maxAge)
                throw stepUp
            }
            do {
                if let reauthenticate {
                    try await reauthenticate(maxAge)
                } else if client.reauthenticationMethod() == .flow {
                    try await reauthenticateWithFlow(maxAge: maxAge)
                } else {
                    _ = try await client.reauthenticate(maxAge: maxAge)
                }
            } catch {
                throw ThunderIDError(
                    code: .stepUpRequired,
                    message: stepUp.message,
                    underlyingError: error,
                    serverError: stepUp.serverError,
                    authenticationChallenge: stepUp.authenticationChallenge
                )
            }
            return try await operation()
        }
    }

    /// Shows the sign-in flow in a sheet (``ReauthenticationRequest``) and waits until it completes for the
    /// signed-in user or is closed. A new request ends one still open.
    func reauthenticateWithFlow(maxAge: Int?) async throws {
        guard let applicationId = (try? client.getConfiguration())?.applicationId, !applicationId.isEmpty else {
            throw ThunderIDError(code: .invalidConfiguration, message: "applicationId is required to sign in again")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reauthenticationRequest?.finish(.failure(Self.reauthenticationCancelled))
            reauthenticationRequest = ReauthenticationRequest(
                applicationId: applicationId,
                maxAge: maxAge,
                continuation: continuation
            )
        }
    }

    /// Ends `request`: completed when `result` succeeds, cancelled otherwise. A request that a newer one has
    /// replaced is already ended, so a late completion from its sheet changes nothing.
    func finishReauthentication(_ request: ReauthenticationRequest, _ result: Result<Void, Error>) {
        if reauthenticationRequest?.id == request.id { reauthenticationRequest = nil }
        request.finish(result)
    }

    static let reauthenticationCancelled = ThunderIDError(
        code: .authenticationFailed,
        message: "The sign-in was closed before it finished"
    )
}

/// A re-sign-in the provider shows as a sheet that runs the sign-in flow.
final class ReauthenticationRequest: Identifiable {
    let id = UUID()
    let applicationId: String
    let maxAge: Int?
    private var continuation: CheckedContinuation<Void, Error>?

    init(applicationId: String, maxAge: Int?, continuation: CheckedContinuation<Void, Error>) {
        self.applicationId = applicationId
        self.maxAge = maxAge
        self.continuation = continuation
    }

    /// Resumes the waiting caller once.
    func finish(_ result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
