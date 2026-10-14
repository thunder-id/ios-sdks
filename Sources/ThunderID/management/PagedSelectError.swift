// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where a failed page load should get its display text from.
///
/// `message` is present only when the loader threw a ``ThunderIDError``, and takes precedence
/// when it is. When it is absent, the caller falls back to a generic, translatable message
/// (`i18n.resolve("userSelect.loadError")`) — this type only records *that* a load failed, not
/// what to say about it, keeping this module free of i18n concerns the same way
/// ``mapCredentialError`` is.
public struct PagedSelectFailure: Equatable {
    public let message: String?

    public init(message: String?) {
        self.message = message
    }
}

/// Maps a `FetchPagedOptions` loader failure onto what a picker should show.
///
/// The loader is consumer-supplied — it is not guaranteed to throw a ``ThunderIDError`` the way
/// `client.users.list` does — so only a ``ThunderIDError``'s message is trusted for direct
/// display; anything else (a bare `Error`, an upstream exception with an unreviewed message)
/// carries no message, and the caller shows the generic fallback instead.
public func mapPagedSelectError(_ error: Error) -> PagedSelectFailure {
    PagedSelectFailure(message: (error as? ThunderIDError)?.message)
}
