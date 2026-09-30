// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Whether a loader's reported next offset is safe to follow: `nil` (exhausted) or an integer past
/// the request offset. Anything else would loop or go backwards.
public func isAdvancingPageOffset(_ requestOffset: Int, _ nextOffset: Int?) -> Bool {
    guard let nextOffset else { return false }
    return nextOffset > requestOffset
}

/// Offset of the next page: the request offset plus the number of items the backend returned, or
/// `nil` once the list is exhausted.
public func computeNextPageOffset(_ requestOffset: Int, count: Int, totalResults: Int?) -> Int? {
    guard count > 0 else { return nil }
    let next = requestOffset + count
    if let totalResults, next >= totalResults { return nil }
    return next
}

/// Converts one raw item into an option using `mapping`: the mapped value is submitted and the
/// mapped label is shown, falling back to the value. `nil` when the mapping has no value for the item.
public func toPagedSelectOption<Item>(_ item: Item, mapping: PagedSelectOptionMapping<Item>) -> PagedSelectOption? {
    guard let value = mapping.value(item) else { return nil }
    return PagedSelectOption(label: mapping.label(item) ?? value, value: value)
}

/// Converts a page of raw items into options, dropping any item the mapping has no value for.
public func toPagedSelectOptions<Item>(
    _ items: [Item],
    mapping: PagedSelectOptionMapping<Item>
) -> [PagedSelectOption] {
    items.compactMap { toPagedSelectOption($0, mapping: mapping) }
}

/// Appends `incoming` to `existing`, keeping each value at its first position and taking the
/// newest data when a value repeats (offset paging can return the same item on two pages).
public func dedupePagedSelectOptions(
    _ existing: [PagedSelectOption],
    _ incoming: [PagedSelectOption]
) -> [PagedSelectOption] {
    var order: [String] = []
    var byValue: [String: PagedSelectOption] = [:]
    for option in existing + incoming {
        if byValue[option.value] == nil {
            order.append(option.value)
        }
        byValue[option.value] = option
    }
    return order.compactMap { byValue[$0] }
}
