// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

// Attribute names that are always readonly regardless of schema mutability (data contract).
private let readonlyFields: Set<String> = ["attributes", "id", "isReadOnly", "ouId", "username", "sub"]

// Default logical-name -> attribute-path fallback mappings.
private let defaultAttributeMappings: [String: [String]] = [
    "email": ["emails", "email"],
    "firstName": ["name.givenName", "given_name"],
    "lastName": ["name.familyName", "family_name"],
    "picture": ["profile", "profileUrl", "picture", "URL"],
    "username": ["userName", "username", "user_name"]
]

/// A schema-described profile field merged with its current value, ready to render.
public struct ProfileField: Identifiable {
    public let name: String
    public let schema: AttributeSchema
    public let rawValue: Any?
    public let isReadonly: Bool
    public let isMultiValued: Bool

    public var id: String { name }
}

/// Every non-credential schema attribute is shown by default.
func buildProfileFields(schema: [String: AttributeSchema], profile: ThunderID.UserProfile) -> [ProfileField] {
    schema
        .filter { $0.value.credential != true }
        .sorted { $0.key < $1.key }
        .map { name, attr in
            let rawValue = profile.attributes[name]?.value
            return ProfileField(
                name: name,
                schema: attr,
                rawValue: rawValue,
                isReadonly: attr.readOnly == true || attr.mutability == "READ_ONLY" || readonlyFields.contains(name),
                isMultiValued: rawValue is [AnyCodable]
            )
        }
}

/// Builds a read-only field list directly from JWT/userinfo claims (no schema to save against).
func buildProfileFieldsFromClaims(_ user: User?) -> [ProfileField] {
    let claims = user?.profileClaims ?? [:]
    return claims
        .compactMap { key, value -> (key: String, formatted: String)? in
            guard let formatted = formatClaim(value.value) else { return nil }
            return (key, formatted)
        }
        .sorted { claimLabel($0.key).lowercased() < claimLabel($1.key).lowercased() }
        .map { key, formatted in
            ProfileField(
                name: key,
                schema: AttributeSchema(displayName: claimLabel(key), readOnly: true, type: "STRING"),
                rawValue: formatted,
                isReadonly: true,
                isMultiValued: false
            )
        }
}

func formatClaim(_ value: Any?) -> String? {
    switch value {
    case let text as String: return text.isEmpty ? nil : text
    case let flag as Bool: return flag ? "Yes" : "No"
    case let number as Int: return String(number)
    case let number as Double: return String(number)
    case let list as [AnyCodable]:
        let items = list.compactMap { formatClaim($0.value) }
        return items.isEmpty ? nil : items.joined(separator: ", ")
    default: return nil
    }
}

/// Humanizes a claim key for display: `given_name` -> "Given Name".
func claimLabel(_ key: String) -> String {
    key
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}

func claimsDisplayName(_ user: User?) -> String {
    guard let user else { return "Guest" }
    let fullName = [user["given_name"] as? String, user["family_name"] as? String]
        .compactMap { $0?.isEmpty == false ? $0 : nil }
        .joined(separator: " ")
    if !fullName.isEmpty { return fullName }
    return user.displayName ?? user.username ?? user.email ?? "Guest"
}

/// Validates an edited field value against its schema: required first, then regex.
func validateField(_ schema: AttributeSchema, _ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if schema.required == true && trimmed.isEmpty {
        return "userProfile.validation.required"
    }
    if let pattern = schema.regex, !pattern.isEmpty, !trimmed.isEmpty,
       let regex = try? NSRegularExpression(pattern: pattern) {
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if regex.firstMatch(in: trimmed, range: range) == nil {
            return "userProfile.validation.pattern"
        }
    }
    return nil
}

/// Resolves a logical attribute name (firstName, email, picture...) to a value on `profile` by
/// trying each candidate path in `mappings` in order, falling back to the built-in defaults.
func mapAttribute(_ key: String, _ mappings: [String: [String]], _ profile: ThunderID.UserProfile) -> String? {
    guard let candidates = mappings[key] ?? defaultAttributeMappings[key] else {
        return profile.attributes[key].map { "\($0.value)" }
    }
    for path in candidates {
        if let resolved = resolveAttributePath(profile.attributes, path) {
            return "\(resolved)"
        }
    }
    return nil
}

/// Combines mapped firstName/lastName into a display name, falling back to username then id.
func computeDisplayName(_ mappings: [String: [String]], _ profile: ThunderID.UserProfile) -> String {
    let fullName = [
        mapAttribute("firstName", mappings, profile),
        mapAttribute("lastName", mappings, profile)
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .trimmingCharacters(in: .whitespaces)
    if !fullName.isEmpty { return fullName }
    return mapAttribute("username", mappings, profile) ?? profile.id
}

private func resolveAttributePath(_ attributes: [String: AnyCodable], _ path: String) -> Any? {
    var current: Any? = attributes
    for segment in path.split(separator: ".") {
        guard let dict = current as? [String: AnyCodable] else { return nil }
        current = dict[String(segment)]?.value
    }
    return current
}

/// Renders a raw field value for display/editing: joins list values, blanks out complex ones.
public func stringifyFieldValue(_ rawValue: Any?) -> String {
    switch rawValue {
    case nil: return ""
    case let list as [AnyCodable]: return list.map { "\($0.value)" }.joined(separator: ", ")
    case is [String: AnyCodable]: return ""
    default: return "\(rawValue ?? "")"
    }
}

/// Builds the nested attributes payload segment for a single dot-path field save.
func buildUpdatePayload(_ name: String, _ value: String, _ isMultiValued: Bool) -> [String: Any] {
    let resolvedValue: Any = isMultiValued
        ? value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        : value
    return buildNestedMap(name.split(separator: ".").map(String.init), resolvedValue)
}

private func buildNestedMap(_ segments: [String], _ value: Any) -> [String: Any] {
    guard segments.count > 1 else { return [segments[0]: value] }
    return [segments[0]: buildNestedMap(Array(segments.dropFirst()), value)]
}

// Recursively merges overrides onto base. The backend requires every required attribute present
// in any save, so a single-field edit still needs the rest of the profile's attributes carried along.
func deepMergeAttributes(_ base: [String: Any], _ overrides: [String: Any]) -> [String: Any] {
    var result = base
    for (key, value) in overrides {
        if let baseDict = result[key] as? [String: Any], let overrideDict = value as? [String: Any] {
            result[key] = deepMergeAttributes(baseDict, overrideDict)
        } else {
            result[key] = value
        }
    }
    return result
}

/// Unwraps `AnyCodable` boxes so the result is safe to hand to `JSONSerialization` when saving.
func deepUnwrapAttributes(_ attributes: [String: AnyCodable]) -> [String: Any] {
    attributes.mapValues { deepUnwrapValue($0.value) }
}

private func deepUnwrapValue(_ value: Any) -> Any {
    switch value {
    case let dict as [String: AnyCodable]: return dict.mapValues { deepUnwrapValue($0.value) }
    case let array as [AnyCodable]: return array.map { deepUnwrapValue($0.value) }
    default: return value
    }
}

/// State container passed to the BaseUserProfile builder.
@MainActor
public final class UserProfileState: ObservableObject {
    @Published public fileprivate(set) var profile: ThunderID.UserProfile?
    @Published public fileprivate(set) var fields: [ProfileField] = []
    @Published public fileprivate(set) var displayName: String = ""
    @Published public fileprivate(set) var email: String?
    @Published public fileprivate(set) var isLoading: Bool = false
    @Published public fileprivate(set) var error: String?

    @Published fileprivate var editedValues: [String: String] = [:]
    @Published fileprivate var editingFields: [String: Bool] = [:]
    @Published fileprivate var fieldErrors: [String: String] = [:]

    /// Held here, not as view `@State`, so saves always read the schema the load resolved.
    fileprivate var schema: [String: AttributeSchema] = [:]

    fileprivate var onEdit: (String) -> Void = { _ in }
    fileprivate var onCancel: (String) -> Void = { _ in }
    fileprivate var onFieldChange: (String, String) -> Void = { _, _ in }
    fileprivate var onSave: (String) -> Void = { _ in }

    public func isEditing(_ name: String) -> Bool { editingFields[name] == true }

    public func fieldValue(_ field: ProfileField) -> String {
        editedValues[field.name] ?? stringifyFieldValue(field.rawValue)
    }

    public func fieldError(_ name: String) -> String? { fieldErrors[name] }

    public func edit(_ name: String) { onEdit(name) }

    public func cancel(_ name: String) { onCancel(name) }

    public func setFieldValue(_ name: String, _ value: String) { onFieldChange(name, value) }

    public func save(_ name: String) { onSave(name) }
}

/// Unstyled base variant (spec §8.3).
public struct BaseUserProfile<Content: View>: View {
    @EnvironmentObject private var thunderState: ThunderIDState
    public let attributeMapping: [String: [String]]
    public let onSaved: (() -> Void)?
    public let onError: (() -> Void)?
    public let content: (UserProfileState) -> Content

    @StateObject private var state = UserProfileState()

    public init(
        attributeMapping: [String: [String]] = [:],
        onSaved: (() -> Void)? = nil,
        onError: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (UserProfileState) -> Content
    ) {
        self.attributeMapping = attributeMapping
        self.onSaved = onSaved
        self.onError = onError
        self.content = content
    }

    public var body: some View {
        content(state)
            .task {
                wireCallbacks()
                guard thunderState.fetchUserProfileEnabled else { return }
                await loadProfile()
            }
            // No /users/me - render from thunderState.user's claims (fetchUserProfile == false).
            .task(id: "\(thunderState.user?.sub ?? "")|\(thunderState.fetchUserProfileEnabled)") {
                guard !thunderState.fetchUserProfileEnabled else { return }
                applyClaimsFallback()
            }
    }

    private func applyProfile(_ loadedProfile: ThunderID.UserProfile) {
        state.profile = loadedProfile
        state.fields = buildProfileFields(schema: state.schema, profile: loadedProfile)
        state.displayName = computeDisplayName(attributeMapping, loadedProfile)
        state.email = mapAttribute("email", attributeMapping, loadedProfile)

        // Reflect an edit immediately, without waiting for the next refresh.
        thunderState.mergeUserProfile(loadedProfile)
    }

    private func applyClaimsFallback() {
        let user = thunderState.user
        state.fields = buildProfileFieldsFromClaims(user)
        state.displayName = claimsDisplayName(user)
        state.email = user?.email
        state.error = nil
        state.isLoading = false
    }

    private func loadProfile() async {
        state.isLoading = true
        defer { state.isLoading = false }
        do {
            async let loadedSchema = thunderState.getUserSchema()
            async let loadedProfile = thunderState.client.getUserProfile()
            let (schemaResult, profileResult) = try await (loadedSchema, loadedProfile)
            state.schema = schemaResult
            applyProfile(profileResult)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func editField(_ name: String) {
        guard let field = state.fields.first(where: { $0.name == name }) else { return }
        state.editedValues[name] = stringifyFieldValue(field.rawValue)
        state.editingFields[name] = true
        state.fieldErrors.removeValue(forKey: name)
    }

    private func cancelField(_ name: String) {
        state.editingFields[name] = false
        state.editedValues.removeValue(forKey: name)
        state.fieldErrors.removeValue(forKey: name)
    }

    private func saveField(_ name: String) {
        guard let field = state.fields.first(where: { $0.name == name }) else { return }
        let value = state.editedValues[name] ?? stringifyFieldValue(field.rawValue)
        if let validationKey = validateField(field.schema, value) {
            state.fieldErrors[name] = thunderState.i18n.resolve(validationKey)
            return
        }
        state.fieldErrors.removeValue(forKey: name)
        Task { await performSave(name: name, field: field, value: value) }
    }

    private func performSave(name: String, field: ProfileField, value: String) async {
        state.isLoading = true
        defer { state.isLoading = false }
        do {
            let fieldPayload = buildUpdatePayload(name, value, field.isMultiValued)
            let currentAttributes = state.profile.map { deepUnwrapAttributes($0.attributes) } ?? [:]
            let payload = deepMergeAttributes(currentAttributes, fieldPayload)
            applyProfile(try await thunderState.client.updateUserProfile(payload: payload))
            state.editingFields[name] = false
            state.editedValues.removeValue(forKey: name)
            onSaved?()
        } catch {
            state.fieldErrors[name] = error.localizedDescription
            onError?()
        }
    }

    private func wireCallbacks() {
        state.onEdit = editField
        state.onCancel = cancelField
        state.onFieldChange = { state.editedValues[$0] = $1 }
        state.onSave = saveField
    }
}
