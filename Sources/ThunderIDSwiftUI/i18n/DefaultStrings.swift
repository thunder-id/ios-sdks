// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// English default strings for all ThunderIDSwiftUI components.
public enum DefaultStrings {
    public static let all: [String: String] = [
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
        "signOut.button": "Sign out",
        "signOut.loading": "Signing out…",
        "callback.loading": "Completing sign-in…",
        "callback.error": "Could not complete sign-in",
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
        "languageSwitcher.title": "Language"
    ]
}
