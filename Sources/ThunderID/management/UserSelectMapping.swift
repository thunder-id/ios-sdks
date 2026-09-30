// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Loads one page of users for a `USER_SELECT` picker.
public typealias FetchUsers = FetchPagedOptions<ManagedUser>

/// Chooses which attribute of a ``ManagedUser`` is the label and which is the value, for a
/// picker that does not want the default `display -> username -> email -> id` chain.
public typealias UserSelectOptionMapping = PagedSelectOptionMapping<ManagedUser>

private func attributeText(_ user: ManagedUser, _ key: String) -> String? {
    guard let raw = user.attributes?[key]?.value as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Converts one directory user into an option: submits the user's ID and labels it from
/// `display`, then `username`, then `email`, unless `mapping` says otherwise. `display` equal to
/// the ID is treated as unset, since the backend returns the ID as display when a user type has
/// no display attribute configured.
public func toUserSelectOption(_ user: ManagedUser, mapping: UserSelectOptionMapping? = nil) -> PagedSelectOption? {
    if let mapping {
        return toPagedSelectOption(user, mapping: mapping)
    }

    let display = user.display?.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = (display?.isEmpty == false && display != user.id ? display : nil)
        ?? attributeText(user, "username")
        ?? attributeText(user, "email")
        ?? user.id
    return PagedSelectOption(label: label, value: user.id)
}

/// Converts a page of users into picker options, dropping any user the mapping has no value for.
public func toUserSelectOptions(
    _ users: [ManagedUser], mapping: UserSelectOptionMapping? = nil
) -> [PagedSelectOption] {
    users.compactMap { toUserSelectOption($0, mapping: mapping) }
}

/// Converts a `client.users.list` response into a loader page. The next offset comes from the
/// backend's own `count`, so users dropped by the mapping never shift the paging.
public func toUserSelectPage(
    _ response: ManagedUserListResponse,
    requestOffset: Int,
    mapping: UserSelectOptionMapping? = nil
) -> PagedSelectPage<ManagedUser> {
    PagedSelectPage(
        options: toUserSelectOptions(response.users, mapping: mapping),
        nextOffset: computeNextPageOffset(requestOffset, count: response.count, totalResults: response.totalResults),
        totalResults: response.totalResults
    )
}
