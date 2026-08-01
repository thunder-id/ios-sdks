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

import Foundation

/// Typed error codes for all ThunderID SDK error conditions (spec §10.2).
public enum ThunderIDErrorCode: String {
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

    // Passkey / WebAuthn
    case passkeyNotSupported = "PASSKEY_NOT_SUPPORTED"
    case passkeyCancelled = "PASSKEY_CANCELLED"
    case passkeyNoCredential = "PASSKEY_NO_CREDENTIAL"
    case passkeyFailed = "PASSKEY_FAILED"

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

    public init(code: ThunderIDErrorCode, message: String, underlyingError: Error? = nil) {
        self.code = code
        self.message = message
        self.underlyingError = underlyingError
    }
}

extension ThunderIDError: LocalizedError {
    public var errorDescription: String? { "[\(code.rawValue)] \(message)" }
}
