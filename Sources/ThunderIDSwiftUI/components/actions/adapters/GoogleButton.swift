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

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// "Continue with Google" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
struct GoogleButton: View {
    let label: String
    let isLoading: Bool
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        TriggerButtonStyle(label: label, isLoading: isLoading, disabled: disabled, onTap: onTap) {
            GoogleGlyph()
                .frame(width: 18, height: 18)
        }
    }
}

/// Google "G" glyph. Rendered from a bundled multi-gradient raster asset rather than a hand-drawn
/// `SVGIconPath` shape: Google's current mark uses gradients that can't be reasonably reproduced
/// with the flat-path renderer used by the other adapter buttons.
private struct GoogleGlyph: View {
    var body: some View {
        if let image = GoogleGlyph.resolvedImage() {
            image
                .resizable()
                .scaledToFit()
        } else {
            EmptyView()
        }
    }

    /// Locates the best-matching density variant of the bundled `google@{1x,2x,3x}.png` asset for
    /// the current display, falling back through the other bundled scales (`2x` -> `3x` -> `1x`, in
    /// that preference order) if it's missing. Mirrors `LogoIconCatalog`'s density-fallback search.
    private static func resolvedImage() -> Image? {
        guard let url = resourceUrl() else { return nil }
        #if canImport(UIKit)
        guard let platformImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: platformImage)
        #elseif canImport(AppKit)
        guard let platformImage = NSImage(contentsOfFile: url.path) else { return nil }
        return Image(nsImage: platformImage)
        #else
        return nil
        #endif
    }

    private static func resourceUrl() -> URL? {
        for scale in scaleSearchOrder() {
            if let url = Bundle.module.url(
                forResource: "google@\(scale)x",
                withExtension: "png",
                subdirectory: "ProviderIcons"
            ) {
                return url
            }
        }
        return nil
    }

    private static func scaleSearchOrder() -> [Int] {
        let preferred = min(max(currentDisplayScale(), 1), 3)
        var order = [preferred]
        for scale in [2, 3, 1] where !order.contains(scale) {
            order.append(scale)
        }
        return order
    }

    private static func currentDisplayScale() -> Int {
        #if canImport(UIKit)
        return Int(UIScreen.main.scale.rounded())
        #elseif canImport(AppKit)
        return Int((NSScreen.main?.backingScaleFactor ?? 2).rounded())
        #else
        return 2
        #endif
    }
}
