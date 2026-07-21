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

/// The deterministic result of generating an `avatar:` logo for a letter variant (`.oneLetter`/
/// `.twoLetter`): either two gradient stop colors + a rotation angle, or a flat background color, plus
/// the initials to overlay. Pure data — no rendering dependency — so `ThunderIDSwiftUI` can turn this
/// into a `LinearGradient`/`Color` + `Text` without recomputing the algorithm.
///
/// Never produced for `.anonymousAnimal`/`.anonymousEntity` — those variants are routed straight to
/// the bundled icon catalog by the view layer.
public struct GeneratedAvatar: Sendable, Equatable {
    /// Gradient start color, as a `#RRGGBB` hex string. `nil` when `flatBackgroundHex` is set.
    public let startColorHex: String?
    /// Gradient end color, as a `#RRGGBB` hex string. `nil` when `flatBackgroundHex` is set.
    public let endColorHex: String?
    /// Gradient rotation angle, in degrees, in `[0, 360)`. `nil` when `flatBackgroundHex` is set.
    public let angleDegrees: Double?
    /// Uppercased 1-2 character initials, truncated from `AvatarSpec.content`.
    public let initials: String
    /// Background shape.
    public let shape: AvatarShape
    /// Explicit flat background color (from `AvatarSpec.bg`), if set. When present, render this solid
    /// color instead of building the gradient from `startColorHex`/`endColorHex`/`angleDegrees`.
    public let flatBackgroundHex: String?
}

/// Curated on-brand gradient pairs — `colors` rotates through this set. Must stay byte-for-byte in
/// sync with the web SDK's `AVATAR_PALETTES` in `generateAvatarDataUri.ts` so the same
/// `(content, colors)` pair renders an identical avatar on every ThunderID platform.
private let avatarPalettes: [(start: String, end: String)] = [
    ("#FF7300", "#EF4223"),
    ("#3688FF", "#1d5eb4"),
    ("#5567D5", "#8B6FE8"),
    ("#06b6d4", "#0891b2"),
    ("#10b981", "#059669"),
    ("#ec4899", "#be185d"),
    ("#f59e0b", "#ea580c"),
    ("#8b5cf6", "#6d28d9"),
    ("#5CD1FF", "#3688FF"),
    ("#ef4444", "#b91c1c")
]

/// `h = 0; for each char: h = (h*31 + charCode) mod 2^32`, matching the web SDK's `hashStr`.
/// Iterates UTF-16 code units to match JavaScript's `charCodeAt`, including surrogate halves.
private func hashSeed(_ seed: String) -> UInt32 {
    var hash: UInt32 = 0
    for codeUnit in seed.utf16 {
        hash = hash &* 31 &+ UInt32(codeUnit)
    }
    return hash
}

/// First `maxLength` ASCII alphanumeric characters of `seed`, uppercased. Falls back to `"A"` if
/// `seed` has none, matching the web SDK's `(seed.match(/[A-Za-z0-9]/g) ?? ['A'])`.
private func initials(from seed: String, maxLength: Int) -> String {
    let alphanumerics = seed.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    let chars = alphanumerics.isEmpty ? "A" : String(alphanumerics.prefix(maxLength))
    return chars.uppercased()
}

/// Uppercases and truncates an already-final `content` value to the letter count `variant` calls for.
/// Unlike `initials(from:maxLength:)`, this does no alphanumeric extraction: `content` is assumed to
/// already be the literal, ready-to-render text (the spec parser does no derivation).
private func truncatedContent(_ content: String, variant: AvatarVariant) -> String {
    let maxLength = variant == .oneLetter ? 1 : 2
    return String(content.uppercased().prefix(maxLength))
}

/// Deterministically generates a letter avatar's colors (or flat background), rotation angle, and
/// initials for the given `avatar:` spec. The same `(content, colors, shape, bg)` combination always
/// produces the same result. Only meaningful for `.oneLetter`/`.twoLetter` specs.
public func generateAvatar(_ spec: AvatarSpec) -> GeneratedAvatar {
    let seed = spec.content.isEmpty ? "App" : spec.content
    let initials = truncatedContent(seed, variant: spec.variant)

    if let bg = spec.bg {
        return GeneratedAvatar(
            startColorHex: nil,
            endColorHex: nil,
            angleDegrees: nil,
            initials: initials,
            shape: spec.shape,
            flatBackgroundHex: bg
        )
    }

    let hash = hashSeed(seed)
    let paletteCount = avatarPalettes.count
    let hashIndex = Int(hash % UInt32(paletteCount))
    let idx = ((hashIndex + spec.colors) % paletteCount + paletteCount) % paletteCount
    let palette = avatarPalettes[idx]
    // JS's `h >> 4` is a signed Int32 shift, so hashes >= 2^31 sign-extend to a negative value.
    let rotated = Int((Int32(bitPattern: hash) >> 4) % 360)
    let angle = Double(((rotated + spec.colors * 37) % 360 + 360) % 360)

    return GeneratedAvatar(
        startColorHex: palette.start,
        endColorHex: palette.end,
        angleDegrees: angle,
        initials: initials,
        shape: spec.shape,
        flatBackgroundHex: nil
    )
}

/// Derives ready-to-render `content` for an `avatar:` spec from a raw seed (e.g. a display name or
/// session id) — for callers that don't already have a stored spec's `content` param.
///
/// - `.oneLetter`/`.twoLetter`: the first 1-2 ASCII alphanumeric characters of `seedText`, uppercased,
///   falling back to `"A"` if `seedText` has none.
/// - `.anonymousAnimal`: hash-picks one of the 19 curated animal keys deterministically from
///   `seedText`, using the same polynomial hash as `generateAvatar(_:)`, modulo the sorted list of 19
///   names, so the same seed always picks the same animal. An empty/nil seed still returns some valid
///   animal.
/// - `.anonymousEntity`: same hash-pick, but over the sorted list of 33 curated entity keys.
public func deriveAvatarContent(variant: AvatarVariant, seedText: String?) -> String {
    switch variant {
    case .oneLetter:
        return initials(from: seedText ?? "", maxLength: 1)
    case .twoLetter:
        return initials(from: seedText ?? "", maxLength: 2)
    case .anonymousAnimal:
        return pickAnonymousName(from: anonymousAnimalNames, seedText: seedText)
    case .anonymousEntity:
        return pickAnonymousName(from: anonymousEntityNames, seedText: seedText)
    }
}

/// Hash-picks one of `names`, deterministically from `seedText` when non-empty, or at random
/// otherwise (still returning some valid name from the set).
private func pickAnonymousName(from names: Set<String>, seedText: String?) -> String {
    let sortedNames = names.sorted()
    guard let seedText, !seedText.isEmpty else {
        return sortedNames[Int.random(in: 0..<sortedNames.count)]
    }
    let hash = hashSeed(seedText)
    return sortedNames[Int(hash % UInt32(sortedNames.count))]
}
