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

/// Resolves the curated `anonymous_animal`/`anonymous_entity` icon names (see `anonymousAnimalNames`/
/// `anonymousEntityNames` in `ThunderID`) to the raster images bundled under `Resources/LogoIcons`,
/// via `Bundle.module`.
///
/// The icons ship as plain `<name>@{1x,2x,3x}.png` files rather than an `.xcassets` catalog: SwiftPM's
/// command-line build system (`swift build`/`swift test`) copies `.xcassets` folders verbatim without
/// compiling them to `Assets.car`, so `UIImage(named:in:)`/`NSImage` lookups against an uncompiled
/// catalog fail. Loose density-suffixed files load reliably under both `swift build` and Xcode.
public enum LogoIconCatalog {
    /// The bundled icon for a curated `avatar:variant=anonymous_animal,content=<name>` spec, or `nil`
    /// if `name` isn't one of `anonymousAnimalNames` (callers should fall back to treating the spec as
    /// a plain URL).
    public static func anonymousAnimalImage(named name: String) -> Image? {
        image(category: "anonymous", name: name.lowercased())
    }

    /// The bundled icon for a curated `avatar:variant=anonymous_entity,content=<name>` spec, or `nil`
    /// if `name` isn't one of `anonymousEntityNames` (callers should fall back to treating the spec as
    /// a plain URL).
    public static func anonymousEntityImage(named name: String) -> Image? {
        image(category: "entity", name: name.lowercased())
    }

    private static func image(category: String, name: String) -> Image? {
        guard let url = resourceUrl(category: category, name: name) else {
            return nil
        }
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

    /// Locates the best-matching density variant for the current display, falling back through the
    /// other bundled scales (`2x` -> `3x` -> `1x`, in that preference order) if it's missing.
    private static func resourceUrl(category: String, name: String) -> URL? {
        let subdirectory = "LogoIcons/\(category)"
        for scale in scaleSearchOrder() {
            if let url = Bundle.module.url(
                forResource: "\(name)@\(scale)x",
                withExtension: "png",
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        return nil
    }

    /// Preferred pixel density for the current display, clamped to the bundled `1x`-`3x` range.
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
