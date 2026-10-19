// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Limits and values shared by the select pickers that list management resources.
public enum SelectConstants {
    /// How many options a picker asks for at a time when it is not told otherwise.
    public static let defaultPageSize = 30

    /// The largest page the management API serves. The flow list clamps a larger request and the user
    /// type list rejects it, so loaders cap their request at this size.
    public static let maxPageSize = 100

    /// Batches in a row that add nothing new before the loading helper stops continuing by itself and
    /// waits for the next request.
    public static let maxEmptyContinuations = 3

    /// The pause before the single retry of a failed page request, in nanoseconds.
    public static let retryDelayNanoseconds: UInt64 = 500_000_000
}

/// The page size a picker asks for: the default when none is given, otherwise the given size clamped
/// to at least 1 and at most what the management API serves.
public func resolvePageSize(_ pageSize: Int = SelectConstants.defaultPageSize) -> Int {
    min(max(1, pageSize), SelectConstants.maxPageSize)
}

/// Whether a loader's reported next offset is safe to follow: an integer past the request offset.
/// Anything else would loop or go backwards, so the list ends instead.
public func isAdvancingPageOffset(_ requestOffset: Int, _ nextOffset: Int?) -> Bool {
    guard let nextOffset else { return false }
    return nextOffset > requestOffset
}

/// Offset of the next page: the request offset plus the number of items the backend returned, or
/// `nil` once the list is exhausted.
public func computeNextPageOffset(_ requestOffset: Int, count: Int, totalResults: Int?) -> Int? {
    guard requestOffset >= 0, count > 0 else { return nil }
    let next = requestOffset + count
    if let totalResults, next >= totalResults { return nil }
    return next
}

/// Converts one raw item into an option using `mapping`: the mapped value is submitted and the
/// mapped label is shown, falling back to the value. `nil` when the mapping has no value for the item.
public func toSelectOption<Item>(_ item: Item, mapping: SelectOptionMapping<Item>) -> SelectOption? {
    guard let value = mapping.value(item) else { return nil }
    return SelectOption(label: mapping.label(item) ?? value, value: value)
}

/// Converts a page of raw items into options, dropping any item the mapping has no value for.
public func toSelectOptions<Item>(
    _ items: [Item],
    mapping: SelectOptionMapping<Item>
) -> [SelectOption] {
    items.compactMap { toSelectOption($0, mapping: mapping) }
}

/// Appends `incoming` to `existing`, keeping each value at its first position and taking the
/// newest data when a value repeats (offset paging can return the same item on two pages).
public func dedupeSelectOptions(
    _ existing: [SelectOption],
    _ incoming: [SelectOption]
) -> [SelectOption] {
    var order: [String] = []
    var byValue: [String: SelectOption] = [:]
    for option in existing + incoming {
        if byValue[option.value] == nil {
            order.append(option.value)
        }
        byValue[option.value] = option
    }
    return order.compactMap { byValue[$0] }
}

/// Builds a loader page from one page of a management list response. The next offset comes from the
/// backend's own `count`, so items dropped by the mapping never shift the paging.
public func toListSelectPage<Item>(
    options: [SelectOption],
    count: Int,
    totalResults: Int,
    requestOffset: Int
) -> SelectPage<Item> {
    SelectPage(
        options: options,
        nextOffset: computeNextPageOffset(requestOffset, count: count, totalResults: totalResults),
        totalResults: totalResults
    )
}
