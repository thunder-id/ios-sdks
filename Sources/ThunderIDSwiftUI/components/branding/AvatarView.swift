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

import SwiftUI
import ThunderID

/// Renders a deterministically-generated `avatar:` letter-variant logo (`.oneLetter`/`.twoLetter`) —
/// a gradient (or flat-colored) circle or rounded rectangle, overlaid with initials — matching the
/// web SDK's SVG output pixel-for-pixel (same hash, same palette, same rotation math; see
/// `generateAvatar(_:)` in `ThunderID`).
///
/// Never used for `.anonymousAnimal` — `LogoView` routes that variant straight to
/// `LogoIconCatalog.anonymousAnimalImage(named:)` instead.
public struct AvatarView: View {
    private let avatar: GeneratedAvatar

    /// Creates a view rendering the given `avatar:` spec.
    public init(spec: AvatarSpec) {
        self.avatar = generateAvatar(spec)
    }

    /// Creates a view rendering an already-generated avatar.
    public init(avatar: GeneratedAvatar) {
        self.avatar = avatar
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                background(side: side)
                Text(avatar.initials)
                    .font(.system(size: side * 0.33, weight: .bold, design: .default))
                    .foregroundColor(.white)
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func background(side: CGFloat) -> some View {
        if let flatBackgroundHex = avatar.flatBackgroundHex {
            shape(side: side).fill(Color(hex: flatBackgroundHex))
        } else {
            shape(side: side).fill(gradient)
        }
    }

    private func shape(side: CGFloat) -> AnyShape {
        // A 14/60 corner-radius ratio matches the web SDK's fixed 60x60 viewBox (`rx="14"`).
        avatar.shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: side * 14 / 60))
    }

    private var gradient: LinearGradient {
        let angleDegrees = avatar.angleDegrees ?? 0
        let startColorHex = avatar.startColorHex ?? "#000000"
        let endColorHex = avatar.endColorHex ?? "#000000"
        let radians = angleDegrees * .pi / 180
        let deltaX = cos(radians)
        let deltaY = sin(radians)
        return LinearGradient(
            gradient: Gradient(colors: [Color(hex: startColorHex), Color(hex: endColorHex)]),
            startPoint: UnitPoint(x: 0.5 - deltaX / 2, y: 0.5 - deltaY / 2),
            endPoint: UnitPoint(x: 0.5 + deltaX / 2, y: 0.5 + deltaY / 2)
        )
    }
}

/// Type-erased `Shape`, used to switch between `Circle` and `RoundedRectangle` in `AvatarView`.
private struct AnyShape: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init<ShapeType: Shape>(_ shape: ShapeType) {
        self.pathBuilder = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

private extension Color {
    /// Creates a color from a `#RRGGBB` hex string (as produced by `generateAvatar(_:)`'s palette).
    init(hex: String) {
        var hexValue: UInt64 = 0
        let sanitized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: sanitized).scanHexInt64(&hexValue)
        let red = Double((hexValue & 0xFF0000) >> 16) / 255
        let green = Double((hexValue & 0x00FF00) >> 8) / 255
        let blue = Double(hexValue & 0x0000FF) / 255
        self = Color(red: red, green: green, blue: blue)
    }
}
