// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension SelectMessages {
    static let userSelect = SelectMessages(placeholder: "userSelect.placeholder", empty: "userSelect.empty")
}

private func directoryFetchUsers(_ client: ThunderIDClient, mapping: UserSelectOptionMapping?) -> FetchUsers {
    { request in
        let response = try await client.users.list(
            limit: request.limit, offset: request.offset, filter: request.filter
        )
        return toUserSelectPage(response, requestOffset: request.offset, mapping: mapping)
    }
}

/// Single-user picker for signed-in screens (`USER_SELECT`). It loads the user directory itself, a page
/// at a time, with the signed-in user's access token, and submits the chosen user's ID. Each user is
/// labelled from `display`, then `username`, then `email`, unless `mapping` says otherwise.
///
/// It takes no data source. For any other data source use ``SelectField`` with ``InfiniteOptionsState``.
public struct UserSelectField: View {
    @EnvironmentObject private var state: ThunderIDState
    private let name: String
    private let value: Binding<String>
    private let label: String
    private let placeholder: String?
    private let error: String?
    private let isRequired: Bool
    private let isDisabled: Bool
    private let emptyText: String?
    private let selectedOption: SelectOption?
    private let pageSize: Int
    private let filter: String?
    private let mapping: UserSelectOptionMapping?
    private let onError: ((Error) -> Void)?

    /// - Parameters:
    ///   - pageSize: Users requested at a time, from 1 to 100. Defaults to 30.
    ///   - filter: Narrows the users offered, in the user listing's filter syntax.
    ///   - mapping: Chooses the label and value of each user instead of the default.
    ///   - onError: Called with the error of every failed load. The list itself shows no error.
    public init(
        name: String,
        value: Binding<String>,
        label: String,
        placeholder: String? = nil,
        error: String? = nil,
        required: Bool = false,
        disabled: Bool = false,
        emptyText: String? = nil,
        selectedOption: SelectOption? = nil,
        pageSize: Int = SelectConstants.defaultPageSize,
        filter: String? = nil,
        mapping: UserSelectOptionMapping? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.name = name
        self.value = value
        self.label = label
        self.placeholder = placeholder
        self.error = error
        isRequired = required
        isDisabled = disabled
        self.emptyText = emptyText
        self.selectedOption = selectedOption
        self.pageSize = pageSize
        self.filter = filter
        self.mapping = mapping
        self.onError = onError
    }

    public var body: some View {
        ResourceSelectField(
            name: name,
            value: value,
            label: label,
            placeholder: placeholder,
            error: error,
            isRequired: isRequired,
            isDisabled: isDisabled,
            emptyText: emptyText,
            selectedOption: selectedOption,
            messages: .userSelect,
            resource: "users",
            pageSize: pageSize,
            filter: filter,
            fetchPage: directoryFetchUsers(state.client, mapping: mapping),
            convert: { [mapping] in toUserSelectOptions($0, mapping: mapping) },
            onError: onError
        )
    }
}
