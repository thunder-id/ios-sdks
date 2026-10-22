// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

public extension ThunderIDI18n {
    /// Resolves `key` and substitutes each `{name}` placeholder from `params`.
    func resolve(_ key: String, _ params: [String: String]) -> String {
        params.reduce(resolve(key)) { text, param in
            text.replacingOccurrences(of: "{\(param.key)}", with: param.value)
        }
    }

    /// The translated message to show for a failed management operation. A missing permission
    /// (HTTP 403) and a missing resource (HTTP 404) get their own messages; anything else shows
    /// `fallbackKey`. The server's own error text is never shown. Returns `nil` when `error` is `nil`.
    func managementErrorMessage(_ error: Error?, fallbackKey: String) -> String? {
        guard let error else { return nil }
        switch (error as? ThunderIDError)?.code {
        case .forbidden: return resolve("admin.common.errors.forbidden")
        case .notFound: return resolve("admin.common.errors.not_found")
        default: return resolve(fallbackKey)
        }
    }
}

/// An identity offered by an admin picker.
public struct IdentityCandidate: Identifiable, Hashable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Builds the identity candidates the membership and assignment pickers offer.
enum AdminCandidates {
    static func users(_ page: ManagedUserListResponse?) -> [IdentityCandidate] {
        (page?.users ?? []).map { IdentityCandidate(id: $0.id, label: $0.resolvedName) }
    }

    static func agents(_ page: AgentListResponse?) -> [IdentityCandidate] {
        (page?.agents ?? []).map { IdentityCandidate(id: $0.id, label: $0.name) }
    }

    static func groups(_ page: GroupListResponse?) -> [IdentityCandidate] {
        (page?.groups ?? []).map { IdentityCandidate(id: $0.id, label: $0.name) }
    }
}

extension ThunderIDState {
    /// The organization unit new resources are created in when a component is not given one: the
    /// signed-in user's own `ouId`, from the token claims or, failing that, the user's profile.
    func defaultOuId() async -> String? {
        if let claim = user?["ouId"] as? String, !claim.isEmpty { return claim }
        guard fetchUserProfileEnabled, isSignedIn else { return nil }
        return try? await client.getUserProfile().ouId
    }
}

/// Holds one query for the life of a view and loads it when the view appears.
struct AdminQueryReader<Value, Content: View>: View {
    @StateObject private var query: ResourceQuery<Value>
    let content: (ResourceQuery<Value>) -> Content

    init(
        _ make: @autoclosure @escaping () -> ResourceQuery<Value>,
        @ViewBuilder content: @escaping (ResourceQuery<Value>) -> Content
    ) {
        _query = StateObject(wrappedValue: make())
        self.content = content
    }

    var body: some View {
        content(query).task { await query.refetch() }
    }
}

extension View {
    /// Disables autocapitalization where the platform supports it.
    @ViewBuilder
    func adminNoAutocapitalization() -> some View {
        #if canImport(UIKit)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
