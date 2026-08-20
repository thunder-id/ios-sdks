// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Renders the current user's profile picture, or a deterministic two-color gradient circle with
/// their initials when no picture is available (spec §8.4 Presentation).
public struct UserAvatar: View {
    @EnvironmentObject private var state: ThunderIDState
    private let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        BaseUserAvatar(user: state.user, size: size)
    }
}

/// Unstyled base variant (spec §8.3). Has no `@EnvironmentObject` dependency, so it can be driven by
/// any `User?` value, not just the currently-authenticated session.
///
/// Ported bit-for-bit from the web SDK's `Avatar`/`generateBackgroundColor`/`getInitials`
/// (`packages/react/src/components/primitives/Avatar/Avatar.tsx`) so the same user renders an
/// identical gradient and initials on every ThunderID platform. This is a distinct algorithm from
/// `ThunderIDSwiftUI`'s `AvatarView`/`ThunderID`'s `generateAvatar(_:)`, which power the curated-palette
/// `avatar:` logo specs used for organization/app branding, not user avatars.
public struct BaseUserAvatar: View {
    private let user: User?
    private let size: CGFloat

    public init(user: User?, size: CGFloat = 40) {
        self.user = user
        self.size = size
    }

    public var body: some View {
        Group {
            if let pictureUrl, let url = URL(string: pictureUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsGradient
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialsGradient
            }
        }
        .accessibilityLabel(seedName)
    }

    private var initialsGradient: some View {
        Circle()
            .fill(seedGradient)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    /// Display name used both to derive initials and as the gradient's hash seed, matching the web
    /// SDK's precedence: `given_name` + `family_name` claims, then `displayName`, then `username`,
    /// then `email`, falling back to `"Guest"`.
    private var seedName: String {
        if let givenName = nonBlankString(user?["given_name"]),
           let familyName = nonBlankString(user?["family_name"]) {
            return "\(givenName) \(familyName)"
        }
        if let displayName = nonBlankString(user?.displayName) { return displayName }
        if let username = nonBlankString(user?.username) { return username }
        if let email = nonBlankString(user?.email) { return email }
        return "Guest"
    }

    /// The user's profile picture, checked in the same order as the web SDK: the `picture`
    /// claim first, then a set of common alternate claim keys used by non-standard identity providers.
    private var pictureUrl: String? {
        if let profilePicture = nonBlankString(user?["picture"]) { return profilePicture }
        let alternateKeys = ["profileUrl", "profile", "URL", "avatarUrl", "avatar"]
        for key in alternateKeys {
            if let value = nonBlankString(user?[key]) { return value }
        }
        return nil
    }

    private var initials: String {
        let parts = seedName.split(separator: " ").filter { !$0.isEmpty }
        return parts.prefix(2).map { String($0.first!).uppercased() }.joined()
    }

    private var seedGradient: LinearGradient {
        let seed = UserAvatarSeed(name: seedName)
        let radians = seed.angleDegrees * .pi / 180
        let deltaX = sin(radians)
        let deltaY = -cos(radians)
        return LinearGradient(
            gradient: Gradient(colors: [seed.color1, seed.color2]),
            startPoint: UnitPoint(x: 0.5 - deltaX / 2, y: 0.5 - deltaY / 2),
            endPoint: UnitPoint(x: 0.5 + deltaX / 2, y: 0.5 + deltaY / 2)
        )
    }

    private func nonBlankString(_ value: Any?) -> String? {
        guard let stringValue = value as? String else { return nil }
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Deterministically derives a two-color HSL gradient + rotation angle from a seed string, matching
/// the web SDK's `generateBackgroundColor` (`packages/react/src/components/primitives/Avatar/Avatar.tsx`)
/// bit-for-bit: same 32-bit signed-integer string hash, same hue/saturation/lightness/angle formulas.
private struct UserAvatarSeed {
    let color1: Color
    let color2: Color
    let angleDegrees: Double

    init(name: String) {
        let seed = UserAvatarSeed.hashSeed(name)
        let hue1 = (2 * seed) % 360
        let hue2 = (hue1 + 60 + (seed % 120)) % 360
        let saturation = 70 + (seed % 20)
        let lightness1 = 55 + (seed % 15)
        let lightness2 = 60 + ((2 * seed) % 15)
        self.color1 = Color(hue: hue1, saturation: saturation, lightness: lightness1)
        self.color2 = Color(hue: hue2, saturation: saturation, lightness: lightness2)
        self.angleDegrees = Double(45 + (seed % 91))
    }

    /// JS 32-bit signed integer string hash: `((acc << 5) - acc + charCode)` per UTF-16 code unit,
    /// with silent 32-bit overflow wraparound. Swift's `Int32` traps on overflow by default, so the
    /// wrapping operators `&+`/`&-`/`&<<` are required here.
    private static func hashSeed(_ name: String) -> Int {
        var hash: Int32 = 0
        for scalar in name.unicodeScalars {
            // Guards against out-of-Int32-range code points; realistic names are BMP so this is a
            // no-op in practice.
            let code = Int32(scalar.value & 0xFFFF)
            hash = (hash &<< 5) &- hash &+ code
        }
        return hash == Int32.min ? 0 : abs(Int(hash))
    }
}

private extension Color {
    /// Creates a color from HSL components (hue in degrees, saturation/lightness as percentages),
    /// using the standard HSL-to-RGB conversion. This is distinct from SwiftUI's built-in
    /// `Color(hue:saturation:brightness:)`, which is HSB, not HSL.
    init(hue: Int, saturation: Int, lightness: Int) {
        let hueFraction = Double(hue) / 360
        let saturationFraction = Double(saturation) / 100
        let lightnessFraction = Double(lightness) / 100

        let chroma = (1 - abs(2 * lightnessFraction - 1)) * saturationFraction
        let huePrime = hueFraction * 6
        let secondary = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightnessFraction - chroma / 2
        let rgb = Color.rgbSextant(huePrime: huePrime, chroma: chroma, secondary: secondary)

        self = Color(red: rgb.red + match, green: rgb.green + match, blue: rgb.blue + match)
    }

    /// Maps a hue-prime value (`hue / 60`) to its unshifted RGB sextant, per the standard HSL-to-RGB
    /// conversion. `match` (the lightness offset) is added by the caller.
    private static func rgbSextant(huePrime: Double, chroma: Double, secondary: Double) -> RGB {
        switch huePrime {
        case 0..<1: return RGB(red: chroma, green: secondary, blue: 0)
        case 1..<2: return RGB(red: secondary, green: chroma, blue: 0)
        case 2..<3: return RGB(red: 0, green: chroma, blue: secondary)
        case 3..<4: return RGB(red: 0, green: secondary, blue: chroma)
        case 4..<5: return RGB(red: secondary, green: 0, blue: chroma)
        default: return RGB(red: chroma, green: 0, blue: secondary)
        }
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }
}
