// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Resolves the name to show for a managed identity: the server's `display` value, then `name`,
/// then the `name`, `given_name` + `family_name` or `username` attribute, then the identifier.
public func resolveManagedIdentityName(
    id: String,
    display: String? = nil,
    name: String? = nil,
    attributes: [String: AnyCodable]? = nil
) -> String {
    if let display, !display.isEmpty { return display }
    if let name { return name }
    let attributes = attributes ?? [:]
    if let attributeName = attributes["name"]?.value as? String { return attributeName }
    let fullName = [attributes["given_name"]?.value as? String, attributes["family_name"]?.value as? String]
        .compactMap { $0?.isEmpty == false ? $0 : nil }
        .joined(separator: " ")
    if !fullName.isEmpty { return fullName }
    if let username = attributes["username"]?.value as? String { return username }
    return id
}

public extension ManagedUser {
    /// The name to show for this user. See ``resolveManagedIdentityName(id:display:name:attributes:)``.
    var resolvedName: String {
        resolveManagedIdentityName(id: id, display: display, attributes: attributes)
    }
}
