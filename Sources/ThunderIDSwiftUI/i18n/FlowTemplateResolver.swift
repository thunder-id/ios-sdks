/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import Foundation

/// Resolves `{{ t(namespace:key) }}` and `{{ meta(dot.path) }}` template literals embedded in
/// server-returned component labels and placeholders, using the `GET /flow/meta` response.
///
/// `{{ t(signin:forms.credentials.title) }}` is resolved via the i18n translations returned by
/// `GET /flow/meta`: the segment before the colon is the namespace, the remainder (which may
/// itself contain dots) is used verbatim as a single key into that namespace's translation map.
///
/// `{{ meta(application.name) }}` is resolved via a dot-path walk over the full meta map.
///
/// Any unrecognised expression is left unchanged, matching the Flutter SDK's
/// `FlowTemplateResolver` (`sdks/flutter/lib/src/flow_template_resolver.dart`).
public struct FlowTemplateResolver {
    private static let templateRegex = try? NSRegularExpression(pattern: "\\{\\{\\s*(.*?)\\s*\\}\\}")

    private let meta: [String: Any]

    public init(meta: [String: Any]) {
        self.meta = meta
    }

    public func resolve(_ text: String?) -> String {
        guard let text, !text.isEmpty else {
            return ""
        }
        guard text.contains("{{"), let regex = Self.templateRegex else {
            return text
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = ""
        var lastEnd = text.startIndex

        regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match, let matchRange = Range(match.range, in: text) else {
                return
            }
            result += text[lastEnd..<matchRange.lowerBound]
            result += replacement(for: match, in: text)
            lastEnd = matchRange.upperBound
        }
        result += text[lastEnd...]
        return result
    }

    private func replacement(for match: NSTextCheckingResult, in text: String) -> String {
        guard match.numberOfRanges > 1, let contentRange = Range(match.range(at: 1), in: text) else {
            return String(text[Range(match.range, in: text)!])
        }
        let content = String(text[contentRange])
        let fullMatch = String(text[Range(match.range, in: text)!])

        if content.hasPrefix("t(") && content.hasSuffix(")") {
            let key = String(content.dropFirst(2).dropLast(1))
            return resolveTranslation(key)
        }
        if content.hasPrefix("meta(") && content.hasSuffix(")") {
            let path = String(content.dropFirst(5).dropLast(1))
            return resolveMeta(path)
        }
        return fullMatch
    }

    private func resolveTranslation(_ key: String) -> String {
        guard let colonIndex = key.firstIndex(of: ":") else {
            return ""
        }
        let namespace = String(key[key.startIndex..<colonIndex])
        let dotKey = String(key[key.index(after: colonIndex)...])

        guard let i18n = meta["i18n"] as? [String: Any],
              let translations = i18n["translations"] as? [String: Any],
              let nsMap = translations[namespace] as? [String: Any] else {
            return ""
        }
        return nsMap[dotKey] as? String ?? ""
    }

    private func resolveMeta(_ path: String) -> String {
        var current: Any? = meta
        for part in path.split(separator: ".") {
            guard let dict = current as? [String: Any] else {
                return ""
            }
            current = dict[String(part)]
        }
        if let stringValue = current as? String {
            return stringValue
        }
        guard let current else {
            return ""
        }
        return "\(current)"
    }
}
