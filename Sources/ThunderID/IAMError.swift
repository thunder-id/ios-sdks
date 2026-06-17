import Foundation

/// Typed error codes for all ThunderID SDK error conditions (spec §10.2).
public enum IAMErrorCode: String {
    // Configuration
    case sdkNotInitialized = "SDK_NOT_INITIALIZED"
    case alreadyInitialized = "ALREADY_INITIALIZED"
    case invalidConfiguration = "INVALID_CONFIGURATION"
    case invalidRedirectUri = "INVALID_REDIRECT_URI"

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

    // Network & Server
    case networkError = "NETWORK_ERROR"
    case requestTimeout = "REQUEST_TIMEOUT"
    case serverError = "SERVER_ERROR"
    case unknownError = "UNKNOWN_ERROR"
}

public struct IAMError: Error {
    public let code: IAMErrorCode
    public let message: String
    public let underlyingError: Error?

    public init(code: IAMErrorCode, message: String, underlyingError: Error? = nil) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
    }
}

extension IAMError: LocalizedError {
    public var errorDescription: String? { "[\(code.rawValue)] \(message)" }
}
