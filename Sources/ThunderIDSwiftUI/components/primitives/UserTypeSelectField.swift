// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension PagedSelectMessages {
    /// Wording for a user-type picker.
    static let userTypeSelect = PagedSelectMessages(
        placeholder: "userTypeSelect.placeholder",
        empty: "userTypeSelect.empty",
        loadError: "userTypeSelect.loadError"
    )
}

/// A ``FetchUserTypes`` backed by `client.userTypes.list`, which sends the signed-in user's access token.
private func directoryFetchUserTypes(_ client: ThunderIDClient) -> FetchUserTypes {
    { request in
        let response = try await client.userTypes.list(
            limit: min(request.limit, PagedSelectLimits.maxPageSize),
            offset: request.offset
        )
        return toUserTypeSelectPage(response, requestOffset: request.offset)
    }
}

/// User-type picker for signed-in screens. It loads the user types itself with the signed-in user's access
/// token and shows and submits each type's handle. It takes no data source; for any other data source use
/// ``PagedSelectField``.
public struct UserTypeSelectField: View {
    @EnvironmentObject private var state: ThunderIDState

    private let name: String
    private let value: Binding<String>
    private let label: String
    private let placeholder: String?
    private let error: String?
    private let pageSize: Int

    public init(
        name: String,
        value: Binding<String>,
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        pageSize: Int = 30
    ) {
        self.name = name
        self.value = value
        self.label = label
        self.placeholder = placeholder
        self.error = error
        self.pageSize = pageSize
    }

    public var body: some View {
        PagedSelectField(
            name: name,
            value: value,
            fetch: directoryFetchUserTypes(state.client),
            convert: { _ in [] },
            label: label,
            placeholder: placeholder,
            error: error,
            pageSize: pageSize,
            messages: .userTypeSelect
        )
    }
}
