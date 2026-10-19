// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One batch of options from a loader. A plain list ends the data when it is empty or adds nothing
/// new; a page ends it when `nextCursor` is `nil`.
public enum SelectOptionsBatch<Cursor: Equatable> {
    case list([SelectOption])
    case page(options: [SelectOption], nextCursor: Cursor?)
}

/// What a loader receives when its select asks for more options.
public struct SelectOptionsLoadContext<Cursor: Equatable> {
    /// `nil` on the first call, then the `nextCursor` of the previous batch.
    public let cursor: Cursor?
    /// The options loaded so far.
    public let options: [SelectOption]

    public init(cursor: Cursor?, options: [SelectOption]) {
        self.cursor = cursor
        self.options = options
    }
}

/// Something about a batch that the caller may want to log. The merge itself carried on.
public enum SelectOptionsBatchIssue: Equatable {
    /// The batch added nothing and its cursor did not move: a loader that ignores its cursor.
    case cursorStuck
}

/// The options and cursor after a batch was added, and whether the data has ended.
public struct SelectOptionsMergeResult<Cursor: Equatable> {
    public let cursor: Cursor?
    /// No more batches should be requested.
    public let finished: Bool
    public let issue: SelectOptionsBatchIssue?
    public let options: [SelectOption]
}

/// Adds one loaded batch to the options loaded so far and decides whether the data has ended.
/// Options that are already present are replaced in place by their newer copy. A page ends when its
/// cursor is missing, or when it adds nothing and the cursor did not move. A plain list ends when it
/// adds nothing new. A missing batch counts as an empty list.
///
/// Shared by the SDK modules; it is not part of the supported API and can change in any release.
public func mergeSelectOptionsBatch<Cursor: Equatable>(
    cursor: Cursor?,
    options: [SelectOption],
    batch: SelectOptionsBatch<Cursor>?
) -> SelectOptionsMergeResult<Cursor> {
    let incoming: [SelectOption]
    var nextCursor: Cursor?
    var hasCursorForm = false

    switch batch {
    case .list(let list):
        incoming = list
    case .page(let pageOptions, let pageCursor):
        incoming = pageOptions
        nextCursor = pageCursor
        hasCursorForm = true
    case nil:
        incoming = []
    }

    let merged = dedupeSelectOptions(options, incoming)
    let addedNothing = merged.count == options.count

    guard hasCursorForm else {
        return SelectOptionsMergeResult(cursor: cursor, finished: addedNothing, issue: nil, options: merged)
    }

    let cursorStuck = addedNothing && nextCursor != nil && nextCursor == cursor
    return SelectOptionsMergeResult(
        cursor: nextCursor,
        finished: nextCursor == nil || cursorStuck,
        issue: cursorStuck ? .cursorStuck : nil,
        options: merged
    )
}

/// Loads batches until one adds something new, the data ends, or a few empty batches in a row have
/// been skipped.
///
/// A batch that adds nothing new while more remain would leave the list empty or stuck, so a request
/// for more options would appear to do nothing. The helper keeps going instead, a few batches at most.
///
/// - Parameters:
///   - loadBatch: Loads the next batch.
///   - applyBatch: Adds a batch to the list. Returns `true` when it added nothing while more remain.
///   - isCurrent: Returns `false` once the list was reset or the owner went away, which stops the loop.
///
/// Shared by the SDK modules; it is not part of the supported API and can change in any release.
public func loadUntilOptionsGrow<Batch>(
    loadBatch: () async throws -> Batch,
    applyBatch: (Batch) -> Bool,
    isCurrent: () -> Bool
) async throws {
    var emptyBatches = 0
    while emptyBatches <= SelectConstants.maxEmptyContinuations {
        let batch = try await loadBatch()
        if !isCurrent() || !applyBatch(batch) { return }
        emptyBatches += 1
    }
}
