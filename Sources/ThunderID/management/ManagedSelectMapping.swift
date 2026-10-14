// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Loads one page of authentication flows for an `AUTH_FLOW_SELECT` picker.
public typealias FetchAuthFlows = FetchPagedOptions<ManagedFlow>

/// Loads one page of user types for a `USER_TYPE_SELECT` picker.
public typealias FetchUserTypes = FetchPagedOptions<ManagedUserType>

private func nonEmpty(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

/// Converts one flow into an option: shown by its name (then its handle, then its ID) and submitting its ID.
public func toAuthFlowSelectOption(_ flow: ManagedFlow) -> PagedSelectOption {
    PagedSelectOption(label: nonEmpty(flow.name) ?? nonEmpty(flow.handle) ?? flow.id, value: flow.id)
}

/// Converts one user type into an option shown and submitted by its handle, or `nil` when it has none.
/// Display names are not unique, so they are not used.
public func toUserTypeSelectOption(_ type: ManagedUserType) -> PagedSelectOption? {
    guard let handle = nonEmpty(type.handle) else { return nil }
    return PagedSelectOption(label: handle, value: handle)
}

/// Converts a `client.flows.list` response into a loader page. The next offset comes from the backend's
/// own `count`.
public func toAuthFlowSelectPage(
    _ response: ManagedFlowListResponse,
    requestOffset: Int
) -> PagedSelectPage<ManagedFlow> {
    toListSelectPage(
        options: response.flows.map(toAuthFlowSelectOption),
        count: response.count,
        totalResults: response.totalResults,
        requestOffset: requestOffset
    )
}

/// Converts a `client.userTypes.list` response into a loader page. The next offset comes from the
/// backend's own `count`, so user types without a handle never shift the paging.
public func toUserTypeSelectPage(
    _ response: ManagedUserTypeListResponse,
    requestOffset: Int
) -> PagedSelectPage<ManagedUserType> {
    toListSelectPage(
        options: response.types.compactMap(toUserTypeSelectOption),
        count: response.count,
        totalResults: response.totalResults,
        requestOffset: requestOffset
    )
}
