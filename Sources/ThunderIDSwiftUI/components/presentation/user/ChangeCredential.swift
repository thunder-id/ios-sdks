// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// The form field a credential-update failure belongs to.
public enum CredentialField: Hashable {
    /// The new value failed a server-side check.
    case new
    /// The failure has no single field to blame; show it at form level.
    case form
}

/// The derived state a change-credential form needs to render and to gate submission.
///
/// Mirrors the JavaScript/Android SDKs' `evaluateChangePasswordForm`: there is deliberately no
/// current-value field to evaluate. The self-service credential write endpoint does not verify
/// the account's existing value today, so collecting one would only teach the user a false sense
/// of security.
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

/// Maps a failure from the credential write path onto the field that caused it. `400` is the new
/// value failing a server-side check; anything else has no single field to blame.
public func mapCredentialError(_ error: Error) -> CredentialField {
    guard let thunderError = error as? ThunderIDError, thunderError.code == .invalidInput else { return .form }
    return .new
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

/// State container passed to the ``BaseChangeCredential`` builder.
@MainActor
public final class ChangeCredentialState: ObservableObject {
    @Published public var newValue: String = ""
    @Published public var confirmValue: String = ""
    @Published public fileprivate(set) var error: String?
    @Published public fileprivate(set) var loading: Bool = false
    @Published public fileprivate(set) var success: Bool = false
    @Published public fileprivate(set) var unavailable: Bool = false
    @Published public fileprivate(set) var credentialDisplayName: String
    @Published fileprivate var regex: String?
    @Published fileprivate var policyDescription: String?
    @Published fileprivate var fieldErrors: [CredentialField: String] = [:]

    fileprivate var onSubmit: () -> Void = {}

    init(credentialDisplayName: String) {
        self.credentialDisplayName = credentialDisplayName
    }

    public var evaluation: CredentialFormEvaluation {
        evaluateCredentialForm(newValue: newValue, confirm: confirmValue, regex: regex)
    }

    public func fieldError(_ field: CredentialField) -> String? { fieldErrors[field] }

    public func submit() { onSubmit() }
}

/// Headless change-credential form. Holds the network call, the schema-derived policy and the
/// error routing, and hands its ``ChangeCredentialState`` to a caller-supplied builder, mirroring
/// the `BaseUserProfile` split.
public struct BaseChangeCredential<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    private let attribute: String
    private let credentialDisplayNameOverride: String?
    private let policyRegexOverride: String?
    private let onSuccess: (() -> Void)?
    private let onError: (() -> Void)?
    private let content: (ChangeCredentialState) -> Content

    @StateObject private var state: ChangeCredentialState

    public init(
        attribute: String = "password",
        credentialDisplayName: String? = nil,
        policyRegex: String? = nil,
        onSuccess: (() -> Void)? = nil,
        onError: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (ChangeCredentialState) -> Content
    ) {
        self.attribute = attribute
        self.credentialDisplayNameOverride = credentialDisplayName
        self.policyRegexOverride = policyRegex
        self.onSuccess = onSuccess
        self.onError = onError
        self.content = content
        _state = StateObject(wrappedValue: ChangeCredentialState(
            credentialDisplayName: credentialDisplayName ?? titleCasedCredential(attribute)
        ))
    }

    public var body: some View {
        content(state)
            .task(id: "\(attribute)|\(policyRegexOverride ?? "")") {
                state.onSubmit = submit
                await resolvePolicy()
            }
    }

    private func resolvePolicy() async {
        guard let schema = try? await thunderState.getUserSchema() else { return }
        let entry = schema[attribute]
        state.regex = policyRegexOverride ?? entry?.regex
        state.policyDescription = entry?.description
        state.unavailable = entry?.credential != true
        if credentialDisplayNameOverride == nil, let displayName = entry?.displayName {
            state.credentialDisplayName = displayName
        }
    }

    private func submit() {
        guard state.evaluation.isValid, !state.loading, !state.unavailable else { return }
        Task { await performSubmit() }
    }

    private func performSubmit() async {
        state.error = nil
        state.fieldErrors = [:]
        state.success = false
        state.loading = true
        defer { state.loading = false }
        do {
            try await thunderState.client.updateUserCredentials(attribute: attribute, newValue: state.newValue)
            state.newValue = ""
            state.confirmValue = ""
            state.success = true
            onSuccess?()
        } catch {
            applyError(error)
            onError?()
        }
    }

    private func applyError(_ error: Error) {
        let field = mapCredentialError(error)
        let template = thunderState.i18n.resolve("changeCredential.generic.error")
        let text = substituteCredential(template, state.credentialDisplayName)
        switch field {
        case .new: state.fieldErrors[.new] = text
        case .form: state.error = text
        }
    }
}

/// Styled default change-credential form. Defaults to managing the `password` credential; set
/// `attribute` to manage another one declared on the user type schema (for example `pin`).
/// Renders as a card row, matching `UserProfile`'s field rows, that opens a sheet editor on tap.
///
/// The display name always comes from the schema's `displayName` for `attribute` (falling back to
/// the title-cased attribute name), matching the Android/React/Vue SDKs: an admin renames it from
/// the console, not the app. ``BaseChangeCredential`` still accepts a `credentialDisplayName`
/// override for callers without schema context.
public struct ChangeCredential: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let attribute: String
    public let onSuccess: (() -> Void)?

    public init(attribute: String = "password", onSuccess: (() -> Void)? = nil) {
        self.attribute = attribute
        self.onSuccess = onSuccess
    }

    public var body: some View {
        BaseChangeCredential(attribute: attribute, onSuccess: onSuccess) { state in
            ChangeCredentialRow(state: state, i18n: i18n)
        }
    }
}

private struct ChangeCredentialRow: View {
    @ObservedObject var state: ChangeCredentialState
    let i18n: ThunderIDI18n
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = false

    private func text(_ key: String) -> String { substituteCredential(i18n.resolve(key), state.credentialDisplayName) }

    var body: some View {
        Button { expanded = true } label: {
            HStack {
                Text(text("changeCredential.heading"))
                    .font(.system(size: 16))
                    .foregroundColor(colorScheme.changeCredentialText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme.changeCredentialChevron)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(colorScheme.changeCredentialCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $expanded, onDismiss: resetFields) {
            ChangeCredentialSheet(state: state, i18n: i18n)
        }
        .onChange(of: state.success) { success in
            if success { expanded = false }
        }
    }

    private func resetFields() {
        state.newValue = ""
        state.confirmValue = ""
    }
}

/// Sheet editor `ChangeCredential` opens when its row is tapped, matching `UserProfile`'s
/// Cancel / title / Save header. The card holds the form, or an unavailable message when the
/// schema doesn't declare this attribute as a credential.
private struct ChangeCredentialSheet: View {
    @ObservedObject var state: ChangeCredentialState
    let i18n: ThunderIDI18n
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private func text(_ key: String) -> String { substituteCredential(i18n.resolve(key), state.credentialDisplayName) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.unavailable {
                unavailableBody
            } else {
                formBody
            }

            Spacer()
        }
        .onChange(of: state.success) { success in
            if success { dismiss() }
        }
        .presentationDetents([.fraction(0.35), .medium])
        .presentationDragIndicator(.hidden)
    }

    /// True three-zone header: the title stays centered on the sheet regardless of whether the
    /// trailing action renders, instead of drifting when `Change` is hidden in the unavailable state.
    private var header: some View {
        ZStack {
            Text(state.credentialDisplayName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme.changeCredentialText)

            HStack {
                Button(i18n.resolve("userProfile.cancel")) { dismiss() }
                    .font(.system(size: 17))
                    .foregroundColor(.changeCredentialAccent)
                Spacer()
                if !state.unavailable {
                    Button(i18n.resolve("changeCredential.submitShort")) { state.submit() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.changeCredentialAccent)
                        .disabled(!state.evaluation.isValid || state.loading)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var unavailableBody: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(colorScheme.changeCredentialCard)
                    .frame(width: 52, height: 52)
                Image(systemName: "lock.slash")
                    .font(.system(size: 20))
                    .foregroundColor(colorScheme.changeCredentialTextSecondary)
            }
            .padding(.bottom, 4)

            Text(text("changeCredential.unavailable"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme.changeCredentialText)
                .multilineTextAlignment(.center)
            Text(text("changeCredential.unavailable.description"))
                .font(.system(size: 14))
                .foregroundColor(colorScheme.changeCredentialTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 20)
    }

    @ViewBuilder
    private var formBody: some View {
        let evaluation = state.evaluation
        let newInvalid = !state.newValue.isEmpty && evaluation.patternChecked && !evaluation.patternPassed
        let confirmMismatch = !state.confirmValue.isEmpty && !evaluation.confirmMatches

        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                CredentialSecureField(
                    placeholder: text("changeCredential.new.label"),
                    value: $state.newValue,
                    testId: "thunderid-field-newCredential"
                )
                Divider().background(colorScheme.changeCredentialBorder).padding(.leading, 16)
                CredentialSecureField(
                    placeholder: text("changeCredential.confirm.label"),
                    value: $state.confirmValue,
                    testId: "thunderid-field-confirmCredential"
                )
            }
            .background(colorScheme.changeCredentialCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let newError = state.fieldError(.new) {
                errorText(newError)
            } else if newInvalid {
                errorText(text("changeCredential.new.invalid.error"))
            }
            if confirmMismatch {
                errorText(text("changeCredential.mismatch.error"))
            }
            if let error = state.error {
                errorText(error)
            }

            Text(hint(for: evaluation))
                .font(.system(size: 13))
                .foregroundColor(colorScheme.changeCredentialTextSecondary)
        }
        .padding(.horizontal, 20)
    }

    private func hint(for evaluation: CredentialFormEvaluation) -> String {
        guard evaluation.patternChecked else { return text("changeCredential.description") }
        return state.policyDescription?.isEmpty == false
            ? state.policyDescription!
            : text("changeCredential.requirements.pattern")
    }

    private func errorText(_ message: String) -> some View {
        Text(message).font(.system(size: 12.5)).foregroundColor(colorScheme.changeCredentialError)
    }
}

/// A single credential row: a field whose placeholder is the field's own label, disappearing once
/// the user starts typing (standard `SecureField`/`TextField` placeholder behavior, so no separate
/// label is rendered), plus a trailing show/hide toggle.
private struct CredentialSecureField: View {
    let placeholder: String
    @Binding var value: String
    let testId: String
    @State private var isVisible = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isVisible {
                    TextField(placeholder, text: $value)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: $value)
                        .textContentType(.password)
                }
            }
            .accessibilityIdentifier(testId)

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 15))
                    .foregroundColor(colorScheme.changeCredentialTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 16))
        .foregroundColor(colorScheme.changeCredentialText)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

/// Color tokens for `ChangeCredential`, matching the same light/dark palette `UserProfile` uses
/// (see `UserProfile.swift`'s own `ColorScheme` extension). Kept local to this file rather than
/// shared, following this SDK's existing per-component convention.
private extension ColorScheme {
    var changeCredentialCard: Color { self == .dark ? Color(hex: "111c2e") : Color(hex: "f1f3f7") }
    var changeCredentialText: Color { self == .dark ? Color(hex: "E0EAFF") : Color(hex: "05213F") }
    var changeCredentialError: Color { Color(hex: "d95757") }

    var changeCredentialTextSecondary: Color {
        self == .dark ? Color(hex: "E0EAFF").opacity(0.48) : Color(hex: "5A7085")
    }

    var changeCredentialChevron: Color {
        self == .dark ? Color(hex: "E0EAFF").opacity(0.3) : Color(hex: "5A7085").opacity(0.55)
    }

    var changeCredentialBorder: Color {
        self == .dark ? Color.white.opacity(0.09) : Color(hex: "DDE3EC")
    }
}

private extension Color {
    static let changeCredentialAccent = Color(hex: "3688FF")

    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}
