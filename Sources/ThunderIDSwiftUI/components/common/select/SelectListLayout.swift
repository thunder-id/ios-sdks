// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import ThunderID

/// What the list under the options says about its own state.
enum SelectListStatus: Equatable {
    /// The first options are being fetched.
    case loading
    /// There are no options, nothing is loading and there is nothing more to load.
    case empty
    /// Nothing to say: options are listed, or a "Load more" row is available.
    case none
}

/// Which rows follow the options, decided from the state of the list.
struct SelectListLayout: Equatable {
    let status: SelectListStatus
    /// Whether the "Load more" row is listed. While `loading` it reads "Loading more…" and cannot be chosen.
    let showsLoadMore: Bool

    init(optionCount: Int, loading: Bool, canLoadMore: Bool) {
        if loading && optionCount == 0 {
            status = .loading
        } else if optionCount == 0 && !canLoadMore && !loading {
            status = .empty
        } else {
            status = .none
        }
        // During the first load there is nothing to load more of; after a failed first load the row stays,
        // so choosing it repeats the request.
        showsLoadMore = canLoadMore && (optionCount > 0 || !loading)
    }
}

/// The option that labels `value`: the loaded option with that value, else the one last picked, else
/// `selectedOption`. `nil` when none of them has that value.
func resolveSelectOption(
    for value: String,
    in options: [SelectOption],
    picked: SelectOption?,
    selectedOption: SelectOption?
) -> SelectOption? {
    guard !value.isEmpty else { return nil }
    if let loaded = options.first(where: { $0.value == value }) { return loaded }
    if let picked, picked.value == value { return picked }
    if let selectedOption, selectedOption.value == value { return selectedOption }
    return nil
}
