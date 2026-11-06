// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension FlowInput {
    /// Reads options sent as strings, or as objects with a `value` (and an optional `label`).
    static func decodeOptions(_ container: KeyedDecodingContainer<CodingKeys>) -> [String]? {
        if let values = try? container.decode([String].self, forKey: .options) { return values }
        guard let objects = try? container.decode([[String: AnyCodable]].self, forKey: .options) else { return nil }
        return objects.compactMap { ($0["value"]?.value ?? $0["label"]?.value) as? String }
    }
}
