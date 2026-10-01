// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One row of a `KEY_VALUE_LIST` component, read from the `additionalData` key named in its `source`.
public struct KeyValuePair: Equatable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    /// Reads the pairs a `KEY_VALUE_LIST` renders from the raw value found under its `source` key.
    /// The server publishes them as a JSON-encoded array, since additional data carries strings, so
    /// both an array and its encoding are accepted.
    ///
    /// Entries that are not objects, or that carry no value, are dropped, since an empty row tells
    /// the user nothing. Anything that is not a list of pairs yields none.
    public static func list(from raw: Any?) -> [KeyValuePair] {
        var parsed = raw
        if let text = raw as? String {
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }
            parsed = decoded
        }
        guard let entries = parsed as? [Any] else {
            return []
        }
        return entries.compactMap { entry in
            let fields = (entry as? [String: Any]) ?? (entry as? [String: AnyCodable])?.mapValues(\.value)
            guard let fields, let value = fields["value"] as? String, !value.isEmpty else {
                return nil
            }
            return KeyValuePair(label: fields["label"] as? String ?? "", value: value)
        }
    }
}
