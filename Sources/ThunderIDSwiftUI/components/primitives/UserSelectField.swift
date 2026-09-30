// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension PagedSelectMessages {
    /// Wording for a user picker.
    static let userSelect = PagedSelectMessages(
        placeholder: "userSelect.placeholder",
        empty: "userSelect.empty",
        loadError: "userSelect.loadError"
    )
}

/// A ``FetchUsers`` backed by `client.users.list`, which sends the signed-in user's access token.
private func directoryFetchUsers(_ client: ThunderIDClient) -> FetchUsers {
    { request in
        let response = try await client.users.list(
            limit: request.limit, offset: request.offset, filter: request.filter
        )
        return toUserSelectPage(response, requestOffset: request.offset)
    }
}

/// Single-user picker for signed-in screens. It loads the user directory itself with the signed-in
/// user's access token (the token needs the `system:user:view` permission) and submits the user's
/// ID, labelling each user from `display`, `username`, or `email` unless `mapping` says otherwise.
/// It takes no data source; for any other data source use ``PagedSelectField``.
public struct UserSelectField: View {
    @EnvironmentObject private var state: ThunderIDState

    private let name: String
    private let value: Binding<String>
    private let mapping: UserSelectOptionMapping?
    private let label: String
    private let placeholder: String?
    private let error: String?
    private let pageSize: Int
    private let filter: String?

    public init(
        name: String,
        value: Binding<String>,
        mapping: UserSelectOptionMapping? = nil,
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        pageSize: Int = 30,
        filter: String? = nil
    ) {
        self.name = name
        self.value = value
        self.mapping = mapping
        self.label = label
        self.placeholder = placeholder
        self.error = error
        self.pageSize = pageSize
        self.filter = filter
    }

    public var body: some View {
        PagedSelectField(
            name: name,
            value: value,
            fetch: directoryFetchUsers(state.client),
            convert: { [mapping] in toUserSelectOptions($0, mapping: mapping) },
            label: label,
            placeholder: placeholder,
            error: error,
            pageSize: pageSize,
            filter: filter,
            messages: .userSelect
        )
    }
}
