// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

extension PagedSelectMessages {
    /// Wording for an authentication-flow picker.
    static let authFlowSelect = PagedSelectMessages(
        placeholder: "authFlowSelect.placeholder",
        empty: "authFlowSelect.empty",
        loadError: "authFlowSelect.loadError"
    )
}

/// A ``FetchAuthFlows`` backed by `client.flows.list`, restricted to authentication flows, which sends the
/// signed-in user's access token.
private func directoryFetchAuthFlows(_ client: ThunderIDClient) -> FetchAuthFlows {
    { request in
        let response = try await client.flows.list(
            limit: min(request.limit, PagedSelectLimits.maxPageSize),
            offset: request.offset,
            flowType: .authentication
        )
        return toAuthFlowSelectPage(response, requestOffset: request.offset)
    }
}

/// Authentication-flow picker for signed-in screens. It loads the authentication flows itself with the
/// signed-in user's access token, shows each flow by its name and submits its ID. It takes no data source;
/// for any other data source use ``PagedSelectField``.
public struct AuthFlowSelectField: View {
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
            fetch: directoryFetchAuthFlows(state.client),
            convert: { _ in [] },
            label: label,
            placeholder: placeholder,
            error: error,
            pageSize: pageSize,
            messages: .authFlowSelect
        )
    }
}
