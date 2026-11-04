// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A JSON value of any shape, for claims and attributes whose type the server decides.
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(String.self) {
            value = val
        } else if let val = try? container.decode(Bool.self) {
            value = val
        } else if let val = try? container.decode(Int.self) {
            value = val
        } else if let val = try? container.decode(Double.self) {
            value = val
        } else if let val = try? container.decode([String: AnyCodable].self) {
            value = val
        } else if let val = try? container.decode([AnyCodable].self) {
            value = val
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let val as String: try container.encode(val)
        case let val as Bool: try container.encode(val)
        case let val as Int: try container.encode(val)
        case let val as Double: try container.encode(val)
        case let val as [String: AnyCodable]: try container.encode(val)
        case let val as [AnyCodable]: try container.encode(val)
        default: try container.encodeNil()
        }
    }
}
