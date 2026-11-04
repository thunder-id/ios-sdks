// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Loads one page of users for a `USER_SELECT` picker.
public typealias FetchUsers = FetchSelectPage<ManagedUser>

/// Chooses which attribute of a ``ManagedUser`` is the label and which is the value, for a
/// picker that does not want the default `display -> username -> email -> id` chain.
public typealias UserSelectOptionMapping = SelectOptionMapping<ManagedUser>

private func attributeText(_ user: ManagedUser, _ key: String) -> String? {
    user.attributes?[key]?.value as? String
}

/// The trimmed text, or `nil` when it is empty or only repeats the user's ID.
private func labelText(_ text: String?, for user: ManagedUser) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty, trimmed != user.id else { return nil }
    return trimmed
}

/// Converts one directory user into an option: submits the user's ID and labels it from
/// `display`, then `username`, then `email`, unless `mapping` says otherwise. A label equal to the
/// ID is treated as unset, since the backend returns the ID as display when a user type has no
/// display attribute configured.
public func toUserSelectOption(_ user: ManagedUser, mapping: UserSelectOptionMapping? = nil) -> SelectOption? {
    if let mapping {
        return toSelectOption(user, mapping: mapping)
    }

    let label = labelText(user.display, for: user)
        ?? labelText(attributeText(user, "username"), for: user)
        ?? labelText(attributeText(user, "email"), for: user)
        ?? user.id
    return SelectOption(label: label, value: user.id)
}

/// Converts a page of users into picker options, dropping any user the mapping has no value for.
public func toUserSelectOptions(
    _ users: [ManagedUser], mapping: UserSelectOptionMapping? = nil
) -> [SelectOption] {
    users.compactMap { toUserSelectOption($0, mapping: mapping) }
}

/// Converts a `client.users.list` response into a loader page. The next offset comes from the
/// backend's own `count`, so users dropped by the mapping never shift the paging.
public func toUserSelectPage(
    _ response: ManagedUserListResponse,
    requestOffset: Int,
    mapping: UserSelectOptionMapping? = nil
) -> SelectPage<ManagedUser> {
    toListSelectPage(
        options: toUserSelectOptions(response.users, mapping: mapping),
        count: response.count,
        totalResults: response.totalResults,
        requestOffset: requestOffset
    )
}
