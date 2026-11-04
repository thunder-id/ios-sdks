// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The strings ThunderIDSwiftUI components ship with: English defaults, and a translation for each
/// shipped locale.
public enum DefaultStrings {
    /// The English (`en-US`) strings, the last fallback for every key.
    public static let all: [String: String] = core.merging(AdminDefaultStrings.all) { current, _ in current }

    /// The locales the SDK ships strings for, the same set the JavaScript SDK ships.
    public static let locales: [String] = [
        "en-US", "fr-FR", "hi-IN", "ja-JP", "pt-BR", "pt-PT", "si-LK", "ta-IN", "te-IN"
    ]

    /// The shipped strings for `locale`, matched exactly (`pt-PT`), then by language alone (`pt` or
    /// `pt-AO` gets `pt-BR`, the first shipped `pt` locale). `nil` when no shipped locale matches.
    public static func strings(for locale: String) -> [String: String]? {
        let normalized = locale.replacingOccurrences(of: "_", with: "-")
        if let exact = bundles.first(where: { $0.key.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return exact.value
        }
        let language = normalized.split(separator: "-").first.map { String($0).lowercased() } ?? ""
        guard let match = locales.first(where: { $0.lowercased().hasPrefix("\(language)-") }) else { return nil }
        return bundles[match]
    }

    private static let bundles: [String: [String: String]] = [
        "en-US": all,
        "fr-FR": FrFRStrings.all,
        "hi-IN": HiINStrings.all,
        "ja-JP": JaJPStrings.all,
        "pt-BR": PtBRStrings.all,
        "pt-PT": PtPTStrings.all,
        "si-LK": SiLKStrings.all,
        "ta-IN": TaINStrings.all,
        "te-IN": TeINStrings.all
    ]

    private static let core: [String: String] = [
        "signIn.button": "Sign in",
        "signIn.title": "Sign in",
        "signIn.submit": "Continue",
        "signIn.loading": "Signing in…",
        "signIn.error": "Sign-in failed",
        "signIn.or": "Or",
        "signIn.continueWithGoogle": "Continue with Google",
        "signIn.continueWithGithub": "Continue with GitHub",
        "signIn.federatedError": "Could not start federated sign-in",
        "signUp.button": "Sign up",
        "signUp.title": "Create account",
        "signUp.submit": "Create account",
        "signUp.loading": "Creating account…",
        "signUp.federatedError": "Could not start federated sign-up",
        "signOut.button": "Sign out",
        "signOut.loading": "Signing out…",
        "callback.loading": "Completing sign-in…",
        "callback.error": "Could not complete sign-in",
        "organizationUnitSwitcher.title": "Organization units",
        "organizationUnitSwitcher.current": "Current",
        "organizationUnitSwitcher.loading": "Loading organization units…",
        "organizationUnitSwitcher.switching": "Switching…",
        "organizationUnitSwitcher.empty": "No organization units",
        "organizationUnitSwitcher.previous": "Previous",
        "organizationUnitSwitcher.next": "Next",
        "organizationUnitSwitcher.error.load": "Could not load your organization units. Please try again.",
        "organizationUnitSwitcher.error.switch": "Could not switch to this organization unit. Please try again.",
        "organizationUnitSwitcher.error.unavailable": "This organization unit is not available to this application.",
        "organizationUnitSwitcher.signInRequired": "Sign in again to switch to {name}.",
        "user.anonymous": "Anonymous",
        "userProfile.title": "Profile",
        "userProfile.section": "Personal info",
        "userProfile.save": "Save",
        "userProfile.loading": "Loading profile…",
        "userProfile.saving": "Saving…",
        "userProfile.edit": "Edit",
        "userProfile.cancel": "Cancel",
        "userProfile.error.load": "Failed to load profile.",
        "userProfile.error.save": "Failed to save changes.",
        "userProfile.validation.required": "This field is required.",
        "userProfile.validation.pattern": "This value is not valid.",
        "changeCredential.heading": "Change {credential}",
        "changeCredential.description": "Choose a strong {credentialLower} and don't reuse it for other accounts.",
        "changeCredential.new.label": "New {credential}",
        "changeCredential.confirm.label": "Confirm New {credential}",
        "changeCredential.submit": "Change {credential}",
        "changeCredential.submitShort": "Change",
        "changeCredential.success": "Your {credentialLower} has been updated.",
        "changeCredential.mismatch.error": "{credential}s do not match.",
        "changeCredential.new.invalid.error": "This doesn't meet the required format.",
        "changeCredential.requirements.pattern": "Must match the required format.",
        "changeCredential.generic.error": "An error occurred while updating your {credentialLower}. Please try again.",
        "changeCredential.unavailable": "{credential} changes unavailable",
        "changeCredential.unavailable.description": "Please contact your administrator.",
        "verifyAttribute.heading": "Verify {attribute}",
        "verifyAttribute.subheading": "Enter the code sent to {destination}.",
        "verifyAttribute.subheading.generic": "Enter the code sent to you.",
        "verifyAttribute.subheading.link": "We sent a verification link to {destination}. Open it, then select Done.",
        "verifyAttribute.destination": "Sent to {destination}.",
        "verifyAttribute.code.label": "Verification code",
        "verifyAttribute.submit": "Verify",
        "verifyAttribute.resend": "Resend code",
        "verifyAttribute.required": "This field is required.",
        "verifyAttribute.success": "{attribute} verified.",
        "verifyAttribute.error": "Verification failed. Please try again.",
        "verifyAttribute.verify": "Verify",
        "verifyAttribute.cancel": "Cancel",
        "verifyAttribute.close": "Close",
        "verifyAttribute.done": "Done",
        "verifyAttribute.status.verified": "Verified",
        "verifyAttribute.status.unverified": "Unverified",
                "languageSwitcher.title": "Language",
        "deviceGrant.title": "Authorize a device",
        "deviceGrant.description": "Enter the code shown on your device.",
        "deviceGrant.userCode": "Device code",
        "deviceGrant.submit": "Continue",
        "deviceGrant.loading": "Loading…",
        "deviceGrant.errors.start": "Could not start device verification. Please try again.",
        "deviceGrant.errors.continue": "Could not continue device authorization. Please try again.",
        "deviceGrant.errors.invalidCode": "This code is invalid or no longer available. Try again.",
        "deviceGrant.messages.complete": "Device authorized",
        "deviceGrant.messages.completeDescription": "You can return to your device.",
        "deviceGrant.messages.denied": "Device not authorized",
        "deviceGrant.messages.deniedDescription": "Access was not granted. Return to your device and start again.",
        "deviceGrant.messages.expired": "Code expired",
        "deviceGrant.messages.expiredDescription": "The time to finish ran out. Return to your device and start again.",
        "deviceGrant.messages.failed": "Device authorization failed",
        "deviceGrant.messages.failedDescription": "Return to your device and start again."
    ]
}
