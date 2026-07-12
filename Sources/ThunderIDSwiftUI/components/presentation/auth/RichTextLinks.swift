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
import SwiftUI

/// Renders the constrained HTML subset produced by the Flow Execution API's `RICH_TEXT`
/// components: `<p>`/`<span>` wrappers (stripped, text kept) and `<a href="...">` anchors
/// (rendered as tappable `Link`s). No third-party HTML parser is used — a small regex-based
/// tag walk is sufficient for this fixed subset.
struct RichTextLinks: View {
    let html: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.segments(from: html).enumerated()), id: \.offset) { _, segment in
                if segment.isLink {
                    if let url = segment.url {
                        Link(segment.text, destination: url)
                    } else {
                        // The anchor's href didn't resolve to a usable URL (e.g. the flow meta
                        // response has no configured URL for this link) — still render it
                        // styled as a link, matching the web SDK's CSS-driven `<a>` styling,
                        // which doesn't depend on href being non-empty. Just not tappable.
                        Text(segment.text)
                            .foregroundColor(.accentColor)
                            .underline()
                    }
                } else if !segment.text.isEmpty {
                    Text(segment.text)
                }
            }
        }
    }

    /// A single renderable chunk of rich text: plain text, or a link with its display text.
    /// `isLink` reflects whether the source was an `<a>` element — independent of whether
    /// `url` successfully parsed — so link styling never silently degrades to plain text.
    struct Segment {
        let text: String
        let url: URL?
        let isLink: Bool
    }

    private static let anchorRegex = try? NSRegularExpression(
        pattern: "<a\\s+[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>",
        options: [.dotMatchesLineSeparators]
    )

    static func segments(from html: String) -> [Segment] {
        guard let regex = anchorRegex else {
            return [Segment(text: stripTags(html), url: nil, isLink: false)]
        }

        var segments: [Segment] = []
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var lastEnd = html.startIndex

        regex.enumerateMatches(in: html, range: fullRange) { match, _, _ in
            guard let match,
                  let matchRange = Range(match.range, in: html),
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let innerRange = Range(match.range(at: 2), in: html) else {
                return
            }
            appendTextSegment(String(html[lastEnd..<matchRange.lowerBound]), to: &segments)
            let linkText = stripTags(String(html[innerRange]))
            let href = String(html[hrefRange])
            let url = href.isEmpty ? nil : URL(string: href)
            segments.append(Segment(text: linkText, url: url, isLink: true))
            lastEnd = matchRange.upperBound
        }
        appendTextSegment(String(html[lastEnd...]), to: &segments)
        return segments
    }

    private static func appendTextSegment(_ raw: String, to segments: inout [Segment]) {
        let text = stripTags(raw)
        if !text.isEmpty {
            segments.append(Segment(text: text, url: nil, isLink: false))
        }
    }

    private static func stripTags(_ fragment: String) -> String {
        let withoutTags = fragment.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return withoutTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
