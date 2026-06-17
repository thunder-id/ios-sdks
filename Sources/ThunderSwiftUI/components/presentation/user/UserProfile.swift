import SwiftUI
import ThunderID

/// Editable user profile form. Calls getUserProfile() on appear, updateUserProfile() on save (spec §8.4).
public struct UserProfile: View {
    @EnvironmentObject private var i18n: ThunderI18n
    public let onSaved: (() -> Void)?
    public let onError: (() -> Void)?

    public init(onSaved: (() -> Void)? = nil, onError: (() -> Void)? = nil) {
        self.onSaved = onSaved
        self.onError = onError
    }

    public var body: some View {
        BaseUserProfile(onSaved: onSaved, onError: onError) { profile, fields, isLoading, error, save in
            VStack(alignment: .leading, spacing: 12) {
                Text(i18n.resolve("userProfile.title"))
                    .accessibilityAddTraits(.isHeader)
                if isLoading && profile == nil {
                    Text(i18n.resolve("userProfile.loading"))
                } else if let error {
                    Text(error).foregroundColor(.red)
                } else {
                    ForEach(Array(fields.keys.sorted()), id: \.self) { key in
                        TextField(key, text: fields[key]!)
                            .accessibilityLabel(key)
                            .frame(minHeight: 44)
                    }
                    Button(isLoading
                           ? i18n.resolve("userProfile.saving")
                           : i18n.resolve("userProfile.save")
                    ) { save() }
                        .disabled(isLoading)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding()
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseUserProfile<Content: View>: View {
    @EnvironmentObject private var state: ThunderState
    public let onSaved: (() -> Void)?
    public let onError: (() -> Void)?
    public let content: (
        ThunderID.UserProfile?, [String: Binding<String>], Bool, String?, @escaping () -> Void
    ) -> Content

    @State private var profile: ThunderID.UserProfile?
    @State private var fieldValues: [String: String] = [:]
    @State private var isLoading = false
    @State private var error: String?

    private let editableKeys = ["displayName", "phoneNumbers"]

    public init(
        onSaved: (() -> Void)? = nil,
        onError: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (
            ThunderID.UserProfile?, [String: Binding<String>], Bool, String?, @escaping () -> Void
        ) -> Content
    ) {
        self.onSaved = onSaved
        self.onError = onError
        self.content = content
    }

    public var body: some View {
        let bindings = Dictionary(uniqueKeysWithValues: editableKeys.map { key in
            (key, Binding(
                get: { fieldValues[key] ?? "" },
                set: { fieldValues[key] = $0 }
            ))
        })
        content(profile, bindings, isLoading, error, save)
            .task { await load() }
    }

    private func load() async {
        isLoading = true; error = nil
        do {
            let fetched = try await state.client.getUserProfile()
            for key in editableKeys {
                if let val = fetched.claims[key] {
                    fieldValues[key] = "\(val.value)"
                }
            }
            profile = fetched
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func save() {
        isLoading = true; error = nil
        Task {
            do {
                _ = try await state.client.updateUserProfile(payload: fieldValues)
                isLoading = false
                onSaved?()
            } catch {
                self.error = error.localizedDescription
                isLoading = false
                onError?()
            }
        }
    }
}
