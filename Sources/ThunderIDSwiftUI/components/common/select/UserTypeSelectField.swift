// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension SelectMessages {
    static let userTypeSelect = SelectMessages(placeholder: "userTypeSelect.placeholder", empty: "userTypeSelect.empty")
}

private func directoryFetchUserTypes(_ client: ThunderIDClient) -> FetchUserTypes {
    { request in
        let response = try await client.userTypes.list(limit: request.limit, offset: request.offset)
        return toUserTypeSelectPage(response, requestOffset: request.offset)
    }
}

/// User-type picker for signed-in screens (`USER_TYPE_SELECT`). It loads the user types itself, a page at
/// a time, with the signed-in user's access token, and shows and submits each user type's handle.
///
/// It takes no data source. For any other data source use ``SelectField`` with ``InfiniteOptionsState``.
public struct UserTypeSelectField: View {
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
    private let onError: ((Error) -> Void)?

    /// - Parameters:
    ///   - pageSize: User types requested at a time, from 1 to 100. Defaults to 30.
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
            messages: .userTypeSelect,
            resource: "user types",
            pageSize: pageSize,
            filter: nil,
            fetchPage: directoryFetchUserTypes(state.client),
            convert: { _ in [] },
            onError: onError
        )
    }
}
