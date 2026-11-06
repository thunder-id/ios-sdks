// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Resolves the name to show for an agent: the server's `display` value, then the `name` attribute when
/// it is a non-empty string, then the identifier. An agent's name is an attribute of its agent type, so
/// it has no top-level `name`.
public func resolveAgentName(id: String, display: String? = nil, attributes: [String: AnyCodable]? = nil) -> String {
    if let display, !display.isEmpty { return display }
    if let name = attributes?["name"]?.value as? String, !name.isEmpty { return name }
    return id
}

public extension Agent {
    /// The name to show for this agent. See ``resolveAgentName(id:display:attributes:)``.
    var resolvedName: String {
        resolveAgentName(id: id, display: display, attributes: attributes)
    }
}

public extension BasicAgent {
    /// The name to show for this agent. See ``resolveAgentName(id:display:attributes:)``.
    var resolvedName: String {
        resolveAgentName(id: id, display: display, attributes: attributes)
    }
}
