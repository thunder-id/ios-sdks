// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The OAuth grant types the application components offer.
public enum ApplicationGrantType: String, CaseIterable {
    case authorizationCode = "authorization_code"
    case refreshToken = "refresh_token"
    case clientCredentials = "client_credentials"
}

extension ThunderIDI18n {
    /// The translated status of an application, or an empty string when it has none.
    func applicationStatus(_ status: ApplicationAccessStatus?) -> String {
        switch status?.value?.uppercased() {
        case "ACTIVE": return resolve("admin.applications.status.active")
        case "SUSPENDED": return resolve("admin.applications.status.suspended")
        default: return status?.value ?? ""
        }
    }

    func grantTypeLabel(_ grantType: String) -> String {
        let key = "admin.applications.grant_types.\(grantType)"
        let label = resolve(key)
        return label == key ? grantType : label
    }
}

/// Splits a comma or newline separated list of URIs, dropping blanks.
func applicationURIList(_ text: String) -> [String] {
    text.split { $0 == "," || $0 == "\n" }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// Whether a set of OAuth basics is consistent: at least one grant type, redirect URIs for the
/// authorization code grant, and no client credentials grant on a public client (it has no secret).
func applicationOAuthIsValid(grantTypes: Set<String>, redirectUris: [String], publicClient: Bool) -> Bool {
    guard !grantTypes.isEmpty else { return false }
    if grantTypes.contains(ApplicationGrantType.authorizationCode.rawValue) && redirectUris.isEmpty {
        return false
    }
    return !(publicClient && grantTypes.contains(ApplicationGrantType.clientCredentials.rawValue))
}

extension OAuth2Config {
    /// An OAuth configuration from the basics the application components edit: a public client
    /// authenticates with no secret and must use PKCE; a confidential one uses a client secret.
    static func basics(grantTypes: [String], redirectUris: [String], publicClient: Bool) -> OAuth2Config {
        let codeFlow = grantTypes.contains(ApplicationGrantType.authorizationCode.rawValue)
        var config = OAuth2Config(grantTypes: grantTypes, responseTypes: codeFlow ? ["code"] : [])
        config.redirectUris = redirectUris
        config.publicClient = publicClient
        config.pkceRequired = publicClient ? true : nil
        config.tokenEndpointAuthMethod = publicClient ? "none" : "client_secret_basic"
        return config
    }
}

extension Application {
    /// The OAuth configuration, when the application has one.
    var oauthConfig: OAuth2Config? {
        request.inboundAuthConfig?.first { $0.type == "oauth2" }?.config
    }
}

/// A newly issued client secret, shown once with a notice to copy it now.
struct ApplicationSecretNotice: View {
    let i18n: ThunderIDI18n
    let secret: String
    let onDone: () -> Void

    var body: some View {
        AdminPanel(title: i18n.resolve("admin.applications.secret.title")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(i18n.resolve("admin.applications.secret.notice"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(secret)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("admin-application-secret")
                HStack {
                    Spacer()
                    Button(i18n.resolve("admin.applications.secret.done"), action: onDone)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("admin-application-secret-done")
                }
            }
        }
    }
}

/// The grant types as toggles.
struct ApplicationGrantTypePicker: View {
    let i18n: ThunderIDI18n
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(i18n.resolve("admin.applications.fields.grant_types"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            ForEach(ApplicationGrantType.allCases, id: \.rawValue) { grantType in
                Toggle(
                    i18n.grantTypeLabel(grantType.rawValue),
                    isOn: Binding(
                        get: { selection.contains(grantType.rawValue) },
                        set: { isOn in
                            if isOn {
                                selection.insert(grantType.rawValue)
                            } else {
                                selection.remove(grantType.rawValue)
                            }
                        }
                    )
                )
                .accessibilityIdentifier("admin-field-grant-\(grantType.rawValue)")
            }
        }
    }
}
