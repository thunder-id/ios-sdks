// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A selectable option: `label` is shown, `value` is submitted.
public struct PagedSelectOption: Equatable, Identifiable, Hashable {
    public var id: String { value }
    public let label: String
    public let value: String
    public let disabled: Bool

    public init(label: String, value: String, disabled: Bool = false) {
        self.label = label
        self.value = value
        self.disabled = disabled
    }
}

/// One page request sent to a ``FetchPagedOptions`` loader.
public struct PagedSelectRequest {
    public let limit: Int
    public let offset: Int
    public let filter: String?

    public init(limit: Int, offset: Int, filter: String? = nil) {
        self.limit = limit
        self.offset = offset
        self.filter = filter
    }
}

/// One page returned by a loader. Return ready-made `options`, or raw `items` for the picker to
/// convert with its mapping. `nextOffset` is `nil` on the last page, otherwise it must be greater
/// than the request's `offset`.
public struct PagedSelectPage<Item> {
    public let items: [Item]?
    public let options: [PagedSelectOption]?
    public let nextOffset: Int?
    public let totalResults: Int?

    public init(items: [Item]? = nil, options: [PagedSelectOption]? = nil, nextOffset: Int?, totalResults: Int? = nil) {
        self.items = items
        self.options = options
        self.nextOffset = nextOffset
        self.totalResults = totalResults
    }
}

/// Loads one page of options for `request`. Generic over the raw item type a specialised picker
/// (users, emails, ...) fetches — `PagedSelectRequest`/`PagedSelectPage` stay the same either way.
public typealias FetchPagedOptions<Item> = (PagedSelectRequest) async throws -> PagedSelectPage<Item>

/// Chooses which field of each raw item is the label and which is the value, for a picker that
/// does not want a type's built-in default conversion.
public struct PagedSelectOptionMapping<Item> {
    public let label: (Item) -> String?
    public let value: (Item) -> String?

    public init(label: @escaping (Item) -> String?, value: @escaping (Item) -> String?) {
        self.label = label
        self.value = value
    }
}
