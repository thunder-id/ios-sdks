// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Builds the filter expressions the management list endpoints accept.
public enum ManagementFilter {
    /// `attribute eq "value"`, for example to search users by username. The server matches the whole value.
    ///
    /// Surrounding whitespace is ignored and double quotes, which the expression cannot carry, are removed.
    /// Returns `nil` when the value is blank or the attribute name is not valid.
    public static func equality(attribute: String, value: String) -> String? {
        let cleaned = value.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isValidAttribute = attribute.range(of: #"^\w+(\.\w+)*$"#, options: .regularExpression) != nil
        guard !cleaned.isEmpty, isValidAttribute else { return nil }
        return "\(attribute) eq \"\(cleaned)\""
    }
}
