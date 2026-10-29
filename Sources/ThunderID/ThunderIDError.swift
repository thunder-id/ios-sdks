// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Typed error codes for all ThunderID SDK error conditions (spec §10.2).
public enum ThunderIDErrorCode: String {
    // Configuration
    case sdkNotInitialized = "SDK_NOT_INITIALIZED"
    case alreadyInitialized = "ALREADY_INITIALIZED"
    case invalidConfiguration = "INVALID_CONFIGURATION"
    case invalidRedirectUri = "INVALID_REDIRECT_URI"
    /// The operation does not apply in the configured mode, such as asking for a token when sign-in runs
    /// on a backend, or sending a request to a URL the backend does not proxy.
    case unsupportedOperation = "UNSUPPORTED_OPERATION"

    // Authentication
    case authenticationFailed = "AUTHENTICATION_FAILED"
    case userAccountLocked = "USER_ACCOUNT_LOCKED"
    case userAccountDisabled = "USER_ACCOUNT_DISABLED"
    case sessionExpired = "SESSION_EXPIRED"
    case mfaRequired = "MFA_REQUIRED"
    case mfaFailed = "MFA_FAILED"
    case invalidGrant = "INVALID_GRANT"
    case consentRequired = "CONSENT_REQUIRED"

    // Registration
    case userAlreadyExists = "USER_ALREADY_EXISTS"
    case invalidInput = "INVALID_INPUT"
    case invitationCodeInvalid = "INVITATION_CODE_INVALID"
    case invitationCodeExpired = "INVITATION_CODE_EXPIRED"
    case registrationDisabled = "REGISTRATION_DISABLED"

    // Recovery
    case recoveryFailed = "RECOVERY_FAILED"
    case confirmationCodeInvalid = "CONFIRMATION_CODE_INVALID"
    case confirmationCodeExpired = "CONFIRMATION_CODE_EXPIRED"

    // Verification
    /// The server refused a self user attribute verification: an `ERROR` step or an HTTP 4xx.
    case verificationFailed = "VERIFICATION_FAILED"

    // Passkey / WebAuthn
    case passkeyNotSupported = "PASSKEY_NOT_SUPPORTED"
    case passkeyCancelled = "PASSKEY_CANCELLED"
    case passkeyNoCredential = "PASSKEY_NO_CREDENTIAL"
    case passkeyFailed = "PASSKEY_FAILED"

    // Management
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
    /// An administration flow did not complete: a step refused (its code and reason are in
    /// ``ThunderIDError/flowError``), or the flow finished without the value the operation needed.
    case administrationFlowFailed = "ADMINISTRATION_FLOW_FAILED"
    /// An administration flow asked for input the caller cannot give, so it could not complete.
    case administrationFlowIncomplete = "ADMINISTRATION_FLOW_INCOMPLETE"
    /// The server configures an administration flow for the operation, but that flow no longer exists.
    /// The operation was not performed.
    case administrationFlowNotFound = "ADMINISTRATION_FLOW_NOT_FOUND"
    /// The operation runs only through an administration flow, such as suspending an account, and the
    /// server configures none for it. There is no management API to fall back to, so nothing was done.
    case administrationFlowNotConfigured = "ADMINISTRATION_FLOW_NOT_CONFIGURED"

    // Network & Server
    case networkError = "NETWORK_ERROR"
    case requestTimeout = "REQUEST_TIMEOUT"
    case serverError = "SERVER_ERROR"
    case unknownError = "UNKNOWN_ERROR"
}

public struct ThunderIDError: Error {
    public let code: ThunderIDErrorCode
    public let message: String
    public let underlyingError: Error?
    /// The error the server returned, when a failed response's body was the server's error envelope:
    /// the server's own error code, and its message and description with their translation keys and
    /// parameters. Use it to show a message specific to the server's code. `nil` otherwise.
    public let serverError: ServerError?
    /// The error of the administration flow step that refused, when one did. Set only on the
    /// `administrationFlow*` codes, which together form the administration flow error family.
    public let flowError: FlowError?

    public init(
        code: ThunderIDErrorCode,
        message: String,
        underlyingError: Error? = nil,
        serverError: ServerError? = nil,
        flowError: FlowError? = nil
    ) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
        self.serverError = serverError
        self.flowError = flowError
    }

    /// Whether this error reports an administration flow that did not complete (a refused step, a flow
    /// that asked for more input, a configured flow that no longer exists, or a flow-only operation with
    /// no flow configured).
    public var isAdministrationFlowError: Bool {
        switch code {
        case .administrationFlowFailed, .administrationFlowIncomplete, .administrationFlowNotFound,
             .administrationFlowNotConfigured:
            return true
        default: return false
        }
    }
}

extension ThunderIDError: LocalizedError {
    public var errorDescription: String? { "[\(code.rawValue)] \(message)" }
}
