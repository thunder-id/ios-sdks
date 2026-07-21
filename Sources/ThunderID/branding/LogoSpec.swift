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

/// Background shape baked into a generated `avatar:` logo, matching the web SDK's `AvatarShape`.
public enum AvatarShape: String, Sendable, Equatable {
    case circle
    case rounded
}

/// What's drawn on an `avatar:` logo's background, matching the web SDK's `AvatarVariant`.
public enum AvatarVariant: String, Sendable, Equatable {
    /// A generated gradient avatar overlaid with 1 letter of `AvatarSpec.content`.
    case oneLetter = "one_letter"
    /// A generated gradient avatar overlaid with 2 letters of `AvatarSpec.content`.
    case twoLetter = "two_letter"
    /// One of the 19 curated animal badge icons, selected by `AvatarSpec.content`.
    case anonymousAnimal = "anonymous_animal"
    /// One of the 33 curated entity badge icons (applications, organizations, resource servers),
    /// selected by `AvatarSpec.content`.
    case anonymousEntity = "anonymous_entity"
}

/// Parsed parameters of an `avatar:` logo spec, e.g.
/// `"avatar:shape=circle,variant=two_letter,content=BM,colors=2"`.
public struct AvatarSpec: Sendable, Equatable {
    /// Background shape.
    public let shape: AvatarShape
    /// What's drawn on the background.
    public let variant: AvatarVariant
    /// The final, ready-to-render value: literal initials for `.oneLetter`/`.twoLetter`, or the
    /// literal lowercase animal key for `.anonymousAnimal`. Never a raw seed to derive from — the
    /// parser does no derivation, see `deriveAvatarContent(variant:seedText:)` for that.
    public let content: String
    /// Deterministic gradient/rotation variant index. Any integer; wraps around the palette. Only
    /// affects `.oneLetter`/`.twoLetter`.
    public let colors: Int
    /// Optional explicit flat background color (e.g. `"#FF5733"`), overriding the derived gradient
    /// for letter variants. Has no effect on `.anonymousAnimal`/`.anonymousEntity` (pre-baked raster
    /// icons on this platform can't be recolored, unlike the web SDK's live-rendered SVG).
    public let bg: String?

    public init(shape: AvatarShape, variant: AvatarVariant, content: String, colors: Int, bg: String? = nil) {
        self.shape = shape
        self.variant = variant
        self.content = content
        self.colors = colors
        self.bg = bg
    }
}

/// Result of resolving an application logo spec string into a renderable representation.
///
/// Mirrors the web SDK's `resolveLogoUri`, minus any rendering: this type has no dependency on
/// SwiftUI/UIKit and can be resolved and tested from the core `ThunderID` target. `ThunderIDSwiftUI`
/// is responsible for turning a `ResolvedLogo` into an actual image.
public enum ResolvedLogo: Sendable, Equatable {
    /// An `emoji:<glyph>` spec — the emoji character to render directly.
    case emoji(String)
    /// An `avatar:...` spec — either a deterministically-generated gradient avatar (letter variants)
    /// or a curated badge icon (`.anonymousAnimal`/`.anonymousEntity`).
    case avatar(AvatarSpec)
    /// Anything else — a bare URL, or a spec in no recognized scheme — carried through verbatim so
    /// callers can always attempt to render *something*.
    case url(String)
}

/// The 19 curated `anonymous_animal` keys with a bundled badge icon, lowercase.
public let anonymousAnimalNames: Set<String> = [
    "jackalope", "mink", "otter", "platypus", "quagga", "raccoon", "skunk", "chameleon",
    "dingo", "hedgehog", "dinosaur", "capybara", "chinchilla", "chipmunk", "chupacabra",
    "frog", "giraffe", "hippo", "jackal"
]

/// The 33 curated `anonymous_entity` keys with a bundled badge icon, lowercase. Covers three
/// categories of non-human resources: applications, organizations, and resource servers.
public let anonymousEntityNames: Set<String> = [
    "anchor", "antenna", "anvil", "arch", "bridge", "chevron", "circuit_node", "compass", "cube",
    "diamond", "dome", "gate", "hexagon", "key", "lighthouse", "lock", "obelisk", "octagon",
    "orbit_ring", "parallelogram", "pavilion", "pentagon", "plus_facet", "silo", "spiral", "spire",
    "star", "tower", "townhouse", "triangle_stack", "turbine", "valve", "windmill"
]

private let emojiScheme = "emoji:"
private let avatarScheme = "avatar:"

/// Resolves an application logo spec string — `emoji:<glyph>`,
/// `avatar:shape=...,variant=...,content=...,colors=...,bg=...`, or a bare URL — into a renderable
/// representation.
///
/// A spec in none of the recognized schemes falls back to `.url(spec)` so callers can always render
/// *something* without special-casing.
///
/// - Parameters:
///   - spec: The stored logo spec string.
///   - fallbackSeedText: Seed text used to derive an `avatar:` spec's `content` when the spec itself
///     doesn't carry a `content` param (e.g. an app name to keep the avatar in sync as it changes).
/// - Returns: The resolved logo, ready to render.
///
/// ```swift
/// resolveLogoSpec("emoji:🛡️") // .emoji("🛡️")
/// resolveLogoSpec("avatar:variant=anonymous_animal,content=jackalope") // .avatar(...)
/// resolveLogoSpec("https://example.com/logo.png") // .url("https://example.com/logo.png")
/// ```
public func resolveLogoSpec(_ spec: String, fallbackSeedText: String = "") -> ResolvedLogo {
    if spec.hasPrefix(emojiScheme) {
        return .emoji(String(spec.dropFirst(emojiScheme.count)))
    }

    if spec.hasPrefix(avatarScheme) {
        let params = parseAvatarParams(spec)
        let content = params.content.isEmpty
            ? deriveAvatarContent(variant: params.variant, seedText: fallbackSeedText)
            : params.content
        return .avatar(
            AvatarSpec(
                shape: params.shape,
                variant: params.variant,
                content: content,
                colors: params.colors,
                bg: params.bg
            )
        )
    }

    return .url(spec)
}

/// Parses the comma-separated `key=value` pairs of an `avatar:` spec, e.g.
/// `"avatar:shape=circle,variant=one_letter,content=B,colors=2,bg=#FF5733"`, falling back to defaults
/// for any missing/invalid field.
func parseAvatarParams(_ spec: String) -> AvatarSpec {
    guard spec.hasPrefix(avatarScheme) else {
        return AvatarSpec(shape: .rounded, variant: .twoLetter, content: "", colors: 0, bg: nil)
    }

    let raw = spec.dropFirst(avatarScheme.count)
    var params: [String: String] = [:]
    for pair in raw.split(separator: ",", omittingEmptySubsequences: false) {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let key = parts.first, !key.isEmpty else { continue }
        let value = parts.count > 1 ? String(parts[1]) : ""
        params[key.trimmingCharacters(in: .whitespaces)] = value.trimmingCharacters(in: .whitespaces)
    }

    let shape = params["shape"].flatMap(AvatarShape.init(rawValue:)) ?? .rounded
    let variant = params["variant"].flatMap(AvatarVariant.init(rawValue:)) ?? .twoLetter
    let content = params["content"] ?? ""
    let colors = params["colors"].flatMap { Int($0) } ?? 0
    let bg = params["bg"].flatMap { $0.isEmpty ? nil : $0 }

    return AvatarSpec(shape: shape, variant: variant, content: content, colors: colors, bg: bg)
}
