// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Whether a schema attribute name matches one of `UserAvatar.swift`'s `pictureClaimKeys`, so the
/// profile picture is edited from the avatar itself instead of appearing twice, once there and once
/// as an ordinary row.
func isPictureField(_ name: String) -> Bool {
    pictureClaimKeys.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
}

/// Editable, schema-driven user profile. Each stored email or mobile value shows whether it is verified,
/// when the server reports it, and an unverified one offers a Verify action that runs the
/// `verificationFlowHandle` flow. Saving a changed email opens its verification.
public struct UserProfile: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    public let attributeMapping: [String: [String]]
    public let verificationFlowHandle: String
    public let onSaved: (() -> Void)?
    public let onError: (() -> Void)?

    public init(
        attributeMapping: [String: [String]] = [:],
        verificationFlowHandle: String = AttributeVerification.defaultFlowHandle,
        onSaved: (() -> Void)? = nil,
        onError: (() -> Void)? = nil
    ) {
        self.attributeMapping = attributeMapping
        self.verificationFlowHandle = verificationFlowHandle
        self.onSaved = onSaved
        self.onError = onError
    }

    public var body: some View {
        BaseUserProfile(attributeMapping: attributeMapping, onSaved: onSaved, onError: onError) { state in
            UserProfileContent(state: state, i18n: i18n, verificationFlowHandle: verificationFlowHandle)
        }
    }
}

/// The one sheet the profile shows at a time: a field's editor, or its verification. Saving a changed
/// email swaps the first for the second.
private enum ProfileSheet: Identifiable {
    case edit(ProfileField)
    case verify(ProfileField)

    var id: String {
        switch self {
        case .edit(let field): return "edit-\(field.name)"
        case .verify(let field): return "verify-\(field.name)"
        }
    }
}

/// Renders the loaded profile: avatar header, then a grouped "Personal Info" card whose rows open
/// a bottom-sheet editor on tap, matching the iOS Settings-style grouped-list convention.
private struct UserProfileContent: View {
    @ObservedObject var state: UserProfileState
    let i18n: ThunderIDI18n
    let verificationFlowHandle: String
    @Environment(\.colorScheme) private var colorScheme

    /// Only one field can be mid-edit at a time (`UserProfileState.editingFields` is exclusive in
    /// practice), so the currently-editing field doubles as the sheet's `item`, ahead of the field being
    /// verified. Dismissing the sheet by any means (Save, Cancel, or a swipe-down) routes back through
    /// `state.cancel` or `state.closeVerification` so the underlying state and the sheet's presence never
    /// drift apart.
    private var activeSheet: Binding<ProfileSheet?> {
        Binding(
            get: {
                if let field = state.fields.first(where: { state.isEditing($0.name) }) { return .edit(field) }
                return state.fields.first { $0.name == state.verifyingField }.map(ProfileSheet.verify)
            },
            set: { newValue in
                guard newValue == nil else { return }
                if let field = state.fields.first(where: { state.isEditing($0.name) }) {
                    state.cancel(field.name)
                } else {
                    state.closeVerification()
                }
            }
        )
    }

    /// The picture attribute, if the schema declares one and it isn't readonly: edited from the
    /// avatar's own EDIT badge instead of appearing again as an ordinary "Personal Info" row.
    private var editablePictureField: ProfileField? {
        state.fields.first { isPictureField($0.name) && !$0.isReadonly }
    }

    private var visibleFields: [ProfileField] {
        state.fields.filter { !isPictureField($0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.isLoading && state.profile == nil {
                Text(i18n.resolve("userProfile.loading"))
                    .foregroundColor(colorScheme.userProfileTextSecondary)
            } else if let error = state.error {
                Text(error).foregroundColor(colorScheme.userProfileError)
            } else {
                if !state.displayName.isEmpty {
                    header
                }
                if !visibleFields.isEmpty {
                    section
                }
            }
        }
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .edit(let field):
                ProfileFieldEditSheet(field: field, state: state, i18n: i18n)
            case .verify(let field):
                ProfileVerificationSheet(field: field, state: state, flowHandle: verificationFlowHandle)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.userProfileAccent, Color(red: 0x8B / 255, green: 0xF9 / 255, blue: 0xFA / 255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                UserAvatar(size: 82)
                if let pictureField = editablePictureField {
                    Button { state.edit(pictureField.name) } label: {
                        VStack {
                            Spacer()
                            Text(i18n.resolve("userProfile.edit"))
                                .font(.system(size: 10, weight: .bold))
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.55))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 82, height: 82)
                    .clipShape(Circle())
                    .accessibilityLabel(i18n.resolve("userProfile.edit"))
                }
            }
            VStack(spacing: 2) {
                Text(state.displayName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorScheme.userProfileText)
                    .accessibilityAddTraits(.isHeader)
                if let email = state.email {
                    Text(email)
                        .font(.system(size: 14.5))
                        .foregroundColor(colorScheme.userProfileTextSecondary)
                }
            }
        }
        .padding(.bottom, 28)
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(i18n.resolve("userProfile.section"))
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .foregroundColor(colorScheme.userProfileTextSecondary)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                ForEach(Array(visibleFields.enumerated()), id: \.element.id) { index, field in
                    ProfileFieldRow(field: field, state: state, i18n: i18n)
                    if index < visibleFields.count - 1 {
                        Divider()
                            .background(colorScheme.userProfileBorder)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(colorScheme.userProfileCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct ProfileFieldRow: View {
    let field: ProfileField
    @ObservedObject var state: UserProfileState
    let i18n: ThunderIDI18n
    @Environment(\.colorScheme) private var colorScheme

    private var label: String { field.schema.displayName ?? field.schema.description ?? field.name }
    private var isComplex: Bool { field.schema.type == "COMPLEX" && field.rawValue is [String: AnyCodable] }
    private var isEditable: Bool { !field.isReadonly && !isComplex }

    var body: some View {
        VStack(spacing: 0) {
            rowButton
            if let status = state.verificationStatus(field) {
                ProfileVerificationLine(field: field, status: status, state: state, i18n: i18n)
            }
        }
    }

    private var rowButton: some View {
        Button {
            state.edit(field.name)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colorScheme.userProfileText)
                Spacer()
                if isComplex, let dict = field.rawValue as? [String: AnyCodable] {
                    ComplexValueView(value: dict)
                } else {
                    let text = stringifyFieldValue(field.rawValue)
                    Text(text.isEmpty ? "-" : text)
                        .font(.system(size: 16))
                        .foregroundColor(colorScheme.userProfileTextSecondary)
                }
                if isEditable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme.userProfileChevron)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }
}

/// The field's verification status, and the Verify action when it is unverified. It sits below the row's
/// button, since a button inside another button's label does not receive taps.
private struct ProfileVerificationLine: View {
    let field: ProfileField
    let status: AttributeVerificationStatus
    @ObservedObject var state: UserProfileState
    let i18n: ThunderIDI18n
    @Environment(\.colorScheme) private var colorScheme

    private var isVerified: Bool { status != .unverified }

    private var statusText: String {
        i18n.resolve(isVerified ? "verifyAttribute.status.verified" : "verifyAttribute.status.unverified")
    }

    var body: some View {
        let verifiedAt = verifiedAtText(status, i18n: i18n)
        HStack(spacing: 10) {
            Spacer()
            // The time is shown, not left to a tooltip, and read with the status as one element.
            HStack(spacing: 8) {
                if let verifiedAt {
                    Text(verifiedAt)
                        .font(.system(size: 12))
                        .foregroundColor(colorScheme.userProfileTextSecondary)
                }
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(lineWidth: 1))
                    .foregroundColor(
                        isVerified ? colorScheme.userProfileVerified : colorScheme.userProfileTextSecondary
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([statusText, verifiedAt].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("thunderid-verification-status-\(field.name)")
            if state.canVerify(field) {
                Button(i18n.resolve("verifyAttribute.verify")) { state.verify(field.name) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.userProfileAccent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("thunderid-verify-\(field.name)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

/// "Verified on {date}" for a verified status with a time, formatted for the active locale. A time the SDK
/// cannot parse is shown as the server sent it.
func verifiedAtText(_ status: AttributeVerificationStatus, i18n: ThunderIDI18n) -> String? {
    guard case .verified(let verifiedAt?) = status, !verifiedAt.isEmpty else { return nil }
    let parser = ISO8601DateFormatter()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: i18n.activeLocale))
    let date = (parser.date(from: verifiedAt) ?? fractional.date(from: verifiedAt)).map { $0.formatted(style) }
        ?? verifiedAt
    return i18n.resolve("verifyAttribute.status.verifiedAt").replacingOccurrences(of: "{date}", with: date)
}

/// Sheet that verifies one field. A recorded verification, or Done after a link, shows the profile read
/// again; the user closes the sheet.
private struct ProfileVerificationSheet: View {
    let field: ProfileField
    @ObservedObject var state: UserProfileState
    let flowHandle: String

    var body: some View {
        // Shows the profile the verification read again, so the status updates without a second read.
        let showProfile: (ThunderID.UserProfile?) -> Void = { profile in
            if let profile { state.apply(profile) }
        }
        VerifyAttribute(
            attribute: field.name,
            flowHandle: flowHandle,
            attributeDisplayName: field.schema.displayName,
            onComplete: nil,
            onDone: { state.closeVerification() },
            onCancel: { state.closeVerification() },
            onError: nil,
            onProfileRead: showProfile
        )
        .id(field.name)
        .padding(20)
        .presentationDetents([.medium, .large])
    }
}

/// Full-screen bottom-sheet editor for one field, matching the mock's Cancel / label / Save header.
private struct ProfileFieldEditSheet: View {
    let field: ProfileField
    @ObservedObject var state: UserProfileState
    let i18n: ThunderIDI18n
    @Environment(\.colorScheme) private var colorScheme

    private var label: String { field.schema.displayName ?? field.schema.description ?? field.name }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(i18n.resolve("userProfile.cancel")) { state.cancel(field.name) }
                    .font(.system(size: 17))
                    .foregroundColor(.userProfileAccent)
                Spacer()
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme.userProfileText)
                Spacer()
                Button(i18n.resolve("userProfile.save")) { state.save(field.name) }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.userProfileAccent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 6) {
                ProfileFieldEditor(field: field, state: state)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(colorScheme.userProfileSheetField)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let message = state.fieldError(field.name) {
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundColor(colorScheme.userProfileError)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .presentationDetents([.fraction(0.35), .medium])
        .presentationDragIndicator(.hidden)
    }
}

private struct ProfileFieldEditor: View {
    let field: ProfileField
    @ObservedObject var state: UserProfileState
    @Environment(\.colorScheme) private var colorScheme

    private var label: String { field.schema.displayName ?? field.schema.description ?? field.name }

    var body: some View {
        if field.schema.type == "BOOLEAN" {
            Toggle(isOn: Binding(
                get: { state.fieldValue(field) == "true" },
                set: { state.setFieldValue(field.name, $0 ? "true" : "false") }
            )) {
                EmptyView()
            }
            .labelsHidden()
        } else {
            TextField(label, text: Binding(
                get: { state.fieldValue(field) },
                set: { state.setFieldValue(field.name, $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .foregroundColor(colorScheme.userProfileText)
            .accessibilityLabel(label)
        }
    }
}

private struct ComplexValueView: View {
    let value: [String: AnyCodable]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(value.keys.sorted(), id: \.self) { key in
                Text("\(key): \(value[key].map { "\($0.value)" } ?? "")")
                    .font(.system(size: 13))
                    .foregroundColor(colorScheme.userProfileTextSecondary)
            }
        }
    }
}

/// Color tokens for `UserProfile`, matching the same light/dark hex palette the Quickstart sample's
/// own screens use (see `bgColor`/`textColor`/`mutedColor`/`borderColor`/`cardColor` in
/// `SignInView.swift`/`HomeView.swift`), so the component reads as part of one continuous
/// ThunderID-branded surface instead of falling back to plain iOS system gray in dark mode.
private extension ColorScheme {
    var userProfileCard: Color { self == .dark ? Color(hex: "111c2e") : Color(hex: "ffffff") }
    var userProfileSheetField: Color { self == .dark ? Color(hex: "16233a") : Color(hex: "f1f3f7") }
    var userProfileText: Color { self == .dark ? Color(hex: "E0EAFF") : Color(hex: "05213F") }
    var userProfileError: Color { Color(hex: "d95757") }
    var userProfileVerified: Color { self == .dark ? Color(hex: "4ADE80") : Color(hex: "15803D") }

    var userProfileTextSecondary: Color {
        self == .dark ? Color(hex: "E0EAFF").opacity(0.48) : Color(hex: "5A7085")
    }

    var userProfileChevron: Color {
        self == .dark ? Color(hex: "E0EAFF").opacity(0.3) : Color(hex: "5A7085").opacity(0.55)
    }

    var userProfileBorder: Color {
        self == .dark ? Color.white.opacity(0.09) : Color(hex: "DDE3EC")
    }
}

private extension Color {
    /// ThunderID brand blue, matching the sample's own `primaryBlue` (same value as Android's `ThunderIDPrimary`).
    static let userProfileAccent = Color(hex: "3688FF")

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
