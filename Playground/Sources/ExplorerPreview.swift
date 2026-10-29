// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// Renders the selected ThunderIDSwiftUI component with the current props.
struct ComponentPreview: View {
    let spec: ComponentSpec
    let values: PropValues
    /// Called with an event name whenever the component fires a callback.
    let onEvent: (String) -> Void

    var body: some View {
        if spec.group.hasPrefix("Admin") {
            AdminPreview(id: spec.id, values: values, onEvent: onEvent)
        } else if spec.group == "Custom rendering" {
            CustomRenderPreview(id: spec.id, values: values, onEvent: onEvent)
        } else {
            standardPreview
        }
    }

    @ViewBuilder private var standardPreview: some View {
        switch spec.group {
        case "Actions": actionPreview
        case "User": UserPreview(id: spec.id, values: values, onEvent: onEvent)
        case "Flows": FlowPreview(id: spec.id, values: values, onEvent: onEvent)
        default: miscPreview
        }
    }

    @ViewBuilder private var actionPreview: some View {
        let connected = values.text("variant") == "connected"
        let loading = values.flag("isLoading")
        switch spec.id {
        case "signInButton":
            if connected {
                SignInButton { onEvent("onTap") }
            } else {
                BaseSignInButton(label: values.text("label"), isLoading: loading) { onEvent("action") }
            }
        case "signOutButton":
            if connected {
                SignOutButton { onEvent("onSignOutComplete") }
            } else {
                BaseSignOutButton(label: values.text("label"), isLoading: loading) { onEvent("action") }
            }
        default:
            if connected {
                SignUpButton { onEvent("onTap") }
            } else {
                BaseSignUpButton(label: values.text("label")) { onEvent("action") }
            }
        }
    }

    @ViewBuilder private var miscPreview: some View {
        switch spec.id {
        case "languageSwitcher":
            LanguageSwitcher(locales: ExplorerCatalog.localeList(values.text("locales")))
        case "logoView":
            LogoView(spec: values.text("spec"), fallbackSeedText: values.text("fallbackSeedText"))
                .frame(width: 72, height: 72)
        default:
            GuardPreview(values: values)
        }
    }
}

private struct UserPreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        switch id {
        case "userAvatar":
            avatar
        case "userDropdown":
            UserDropdown(onProfileTap: { onEvent("onProfileTap") }, onSignOutComplete: { onEvent("onSignOutComplete") })
        case "userProfile":
            signedInOnly {
                ThunderIDSwiftUI.UserProfile(onSaved: { onEvent("onSaved") }, onError: { onEvent("onError") })
            }
        case "verifyAttribute":
            signedInOnly {
                // Each showing sends a code or a link, so a new attribute or handle gets a new view identity.
                VerifyAttribute(
                    attribute: values.text("attribute"),
                    flowHandle: values.text("flowHandle"),
                    onComplete: { onEvent("onComplete") },
                    onDone: { onEvent("onDone") },
                    onCancel: { onEvent("onCancel") },
                    onError: { onEvent("onError: \(describe($0))") }
                )
                .id("\(values.text("attribute"))|\(values.text("flowHandle"))")
            }
        default:
            signedInOnly {
                ChangeCredential(attribute: values.text("attribute")) { onEvent("onSuccess") }
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        let size = CGFloat(Double(values.text("size")) ?? 48)
        switch values.text("source") {
        case "session":
            UserAvatar(size: size)
        case "none":
            BaseUserAvatar(user: nil, size: size)
        default:
            BaseUserAvatar(user: User(claims: ["displayName": AnyCodable(values.text("name"))]), size: size)
        }
    }

    @ViewBuilder private func signedInOnly<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if state.isSignedIn {
            content()
        } else {
            PreviewHint(text: "Sign in to load this component. It reads the signed-in user's profile.")
        }
    }
}

private struct FlowPreview: View {
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void

    var body: some View {
        let applicationId = values.text("applicationId")
        if applicationId.isEmpty {
            PreviewHint(text: "Set applicationId, or THUNDERID_APPLICATION_ID in Config.plist.")
        } else if id == "signIn" {
            SignIn(
                applicationId: applicationId,
                onComplete: { onEvent("onComplete") },
                onError: { onEvent("onError: \($0)") }
            )
                .id(applicationId)
        } else {
            SignUp(
                applicationId: applicationId,
                onComplete: { onEvent("onComplete") },
                onError: { onEvent("onError: \($0)") }
            )
                .id(applicationId)
        }
    }
}

private struct GuardPreview: View {
    let values: PropValues

    var body: some View {
        let content = Text(values.text("content")).font(.headline)
        let fallback = Text(values.text("fallback")).foregroundColor(.secondary)
        if values.text("guard") == "SignedOut" {
            SignedOut { content } fallback: { fallback }
        } else {
            SignedIn { content } fallback: { fallback }
        }
    }
}

struct PreviewHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }
}
