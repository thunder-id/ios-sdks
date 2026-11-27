// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Event names: `[prefix.]<type>.<action>`, the type singular and a multi-word action hyphenated, a failure
/// ending in `-failed` and a page ending in `-view`. Also matches the `exclude` patterns.
struct TelemetryNames {
    /// A path segment that is a plain word, kept in a link's path; any other becomes `{id}`.
    private static let plainWord = try? NSRegularExpression(pattern: "^[A-Za-z_-]{1,40}\\z")
    /// The shape of an event name the app reports: lower-case hyphenated words joined by dots.
    private static let eventName = try? NSRegularExpression(
        pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*(?:\\.[a-z0-9]+(?:-[a-z0-9]+)*)+\\z"
    )
    /// What a code the app reports must not hold: an address, a query, a fragment, a space or a URL.
    private static let notACode = try? NSRegularExpression(pattern: "[@?#\\s]|://")

    /// The product prefix, when configured.
    let prefix: String?

    init(prefix: String? = nil) {
        self.prefix = prefix
    }

    /// The full name of an event: the prefix, when set, and the name.
    func full(_ name: String) -> String {
        guard let prefix, !prefix.isEmpty else { return name }
        return "\(prefix).\(name)"
    }

    /// Whether a value matches a pattern: `*` matches the rest of one path segment, `**` the rest of the
    /// value, and anything else must be equal.
    static func matches(_ value: String, _ pattern: String) -> Bool {
        var expression = "^"
        let chars = Array(pattern)
        var idx = 0
        while idx < chars.count {
            let char = chars[idx]
            if char == "*", idx + 1 < chars.count, chars[idx + 1] == "*" {
                expression += ".*"
                idx += 2
                continue
            }
            expression += char == "*" ? "[^/]*" : NSRegularExpression.escapedPattern(for: String(char))
            idx += 1
        }
        // `\z`, not `$`, which would also match before a final line break.
        expression += "\\z"
        guard let regex = try? NSRegularExpression(pattern: expression, options: [.dotMatchesLineSeparators]) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }

    /// A link's path with only its first segment kept, when it is a plain word, and every later segment
    /// replaced by `{id}`, so a token, an id or a name in it is never reported: `/guides/getting-started` is
    /// `/guides/{id}` and `/reset/eyJ...abc/confirm` is `/reset/{id}/{id}`. Empty segments stay.
    static func templatedPath(_ path: String) -> String {
        var seenSegment = false
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .map { part -> String in
                guard !part.isEmpty else { return "" }
                defer { seenSegment = true }
                return !seenSegment && matches(String(part), plainWord) ? String(part) : "{id}"
            }
            .joined(separator: "/")
    }

    /// Whether `name` is an event name an app may report, such as `application.template-pick`.
    static func isEventName(_ name: String) -> Bool {
        matches(name, eventName)
    }

    /// Whether `value` can be reported as a code: at most 64 characters, with no address, query, fragment,
    /// whitespace or URL in it.
    static func isCode(_ value: String) -> Bool {
        value.count <= 64 && !matches(value, notACode)
    }

    private static func matches(_ value: String, _ regex: NSRegularExpression?) -> Bool {
        regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// Whether a value matches any of the patterns.
    static func matchesAny(_ value: String, _ patterns: [String]) -> Bool {
        patterns.contains { matches(value, $0) }
    }

    /// The singular of a collection's path segment: `applications` is `application`, `policies` is
    /// `policy`, and a word that is not a collection stays as it is.
    static func singular(_ segment: String) -> String {
        // A word ending in `-ss` (`access`) or `-us` (`status`) is not a plural.
        if segment.hasSuffix("ss") || segment.hasSuffix("us") { return segment }
        if segment.hasSuffix("ies") { return String(segment.dropLast(3)) + "y" }
        if segment.hasSuffix("sses") || segment.hasSuffix("xes") { return String(segment.dropLast(2)) }
        if segment.hasSuffix("s") { return String(segment.dropLast()) }
        return segment
    }

    /// Whether a path segment names a collection: a plural word by its English spelling.
    static func isCollection(_ segment: String) -> Bool {
        singular(segment) != segment
    }

    /// Whether a route segment is a parameter, such as `:id` or `{id}`.
    static func isParameter(_ segment: String) -> Bool {
        segment.hasPrefix(":") || (segment.hasPrefix("{") && segment.hasSuffix("}")) || segment == "*"
    }

    /// The name of a page from its route pattern, before the prefix:
    ///
    /// - `/applications` is `application.list-view`;
    /// - `/applications/:id` is `application.detail-view`;
    /// - `/applications/create` and `/applications/:id/status` are `application.create-view` and
    ///   `application.status-view`, and `/applications/:id/settings` is `setting.list-view`;
    /// - `/organizations/:org/home` is `organization.home-view`, and `/` is `app.home-view`.
    static func pageName(_ pattern: String) -> String {
        let segments = pattern.split(separator: "/").map(String.init)
        guard let last = segments.last else { return "app.home-view" }
        let owner = { (before: Int) -> String in
            var idx = before
            while idx >= 0 {
                if !isParameter(segments[idx]) { return singular(segments[idx]) }
                idx -= 1
            }
            return "app"
        }
        if isParameter(last) { return "\(owner(segments.count - 2)).detail-view" }
        if isCollection(last) { return "\(singular(last)).list-view" }
        return "\(owner(segments.count - 2)).\(last)-view"
    }
}
