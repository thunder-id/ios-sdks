// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// The form field a credential-update failure belongs to.
public enum CredentialField: Hashable {
    /// The current value is missing or does not match.
    case current
    /// The new value failed a server-side check.
    case new
    /// The failure has no single field to blame; show it at form level.
    case form
}

/// The derived state a change-credential form needs to render and to gate submission.
///
/// The current value is optional, so it does not take part: a user with no value yet sets a first one
/// without it, and the server decides whether one is needed.
public struct CredentialFormEvaluation {
    public let confirmMatches: Bool
    public let meetsPolicy: Bool
    public let isValid: Bool
    /// Whether a regex rule applies, so the requirement hint can be shown.
    public let patternChecked: Bool
    /// Whether the new value satisfies the regex rule (always `true` when none applies).
    public let patternPassed: Bool
}

/// Evaluates a change-credential form against an optional regex policy.
///
/// An uncompilable pattern is treated as passing, matching the Android/JavaScript SDKs: the
/// client stays lenient so a misconfigured schema cannot lock a user out of their own credential
/// change.
public func evaluateCredentialForm(newValue: String, confirm: String, regex: String?) -> CredentialFormEvaluation {
    let patternChecked = !(regex ?? "").isEmpty
    var patternPassed = true
    if patternChecked, let regex, let expression = try? NSRegularExpression(pattern: regex) {
        let range = NSRange(newValue.startIndex..., in: newValue)
        patternPassed = expression.firstMatch(in: newValue, range: range) != nil
    }
    let meetsPolicy = !patternChecked || patternPassed
    let confirmMatches = newValue == confirm
    let isValid = !newValue.isEmpty && !confirm.isEmpty && meetsPolicy && confirmMatches
    return CredentialFormEvaluation(
        confirmMatches: confirmMatches,
        meetsPolicy: meetsPolicy,
        isValid: isValid,
        patternChecked: patternChecked,
        patternPassed: patternPassed
    )
}

/// Server codes the change-credential form maps to its own messages.
enum CredentialErrorCode {
    static let currentRequired = "USR-1047"
    static let currentInvalid = "USR-1048"
    static let recentAuthenticationRequired = "AUTH-4011"
}

/// Maps a failure from the credential write path onto the field that caused it: a missing or wrong current
/// value to the current field, any other `400` to the new value, and the rest, a request for a more recent
/// sign-in included, to the form.
public func mapCredentialError(_ error: Error) -> CredentialField {
    guard let thunderError = error as? ThunderIDError else { return .form }
    switch thunderError.serverError?.code {
    case CredentialErrorCode.currentRequired, CredentialErrorCode.currentInvalid: return .current
    case CredentialErrorCode.recentAuthenticationRequired: return .form
    default: return thunderError.code == .invalidInput ? .new : .form
    }
}

/// Whether the failure asks the user to sign in again before the change can go through.
func credentialNeedsReauthentication(_ error: Error) -> Bool {
    guard let thunderError = error as? ThunderIDError else { return false }
    return thunderError.code == .stepUpRequired
        || thunderError.authenticationChallenge != nil
        || thunderError.serverError?.code == CredentialErrorCode.recentAuthenticationRequired
}

/// The message template for a failed change, from the translation bundle for the codes the form knows,
/// else the server's readable message, else the generic text.
func credentialErrorTemplate(_ error: Error, resolve: (String) -> String) -> String {
    if credentialNeedsReauthentication(error) { return resolve("changeCredential.reauthentication.error") }
    let serverError = (error as? ThunderIDError)?.serverError
    switch serverError?.code {
    case CredentialErrorCode.currentRequired: return resolve("changeCredential.current.required.error")
    case CredentialErrorCode.currentInvalid: return resolve("changeCredential.current.invalid.error")
    default: return serverError?.readableMessage ?? resolve("changeCredential.generic.error")
    }
}

/// Substitutes `{credential}` / `{credentialLower}` into a translation template.
func substituteCredential(_ template: String, _ displayName: String) -> String {
    template
        .replacingOccurrences(of: "{credential}", with: displayName)
        .replacingOccurrences(of: "{credentialLower}", with: displayName.lowercased())
}

/// Title-cases a credential name for use as its default display name, e.g. `pin` -> `Pin`.
func titleCasedCredential(_ name: String) -> String {
    name.isEmpty ? name : name.prefix(1).uppercased() + name.dropFirst()
}
