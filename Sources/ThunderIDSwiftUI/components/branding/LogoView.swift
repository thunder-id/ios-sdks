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

/// Renders an application logo spec string — `emoji:<glyph>`,
/// `avatar:shape=...,variant=...,content=...,colors=...,bg=...`, or a bare URL — parsed with
/// `resolveLogoSpec(_:fallbackSeedText:)`.
///
/// This always renders *something*: an unrecognized spec (or an `anonymous_animal`/`anonymous_entity`
/// name with no bundled icon) falls back to loading it as a plain image URL via `AsyncImage`.
///
/// ```swift
/// LogoView(spec: "avatar:variant=anonymous_animal,content=jackalope")
/// LogoView(spec: "avatar:shape=circle,variant=two_letter,content=BM,colors=2")
/// ```
public struct LogoView: View {
    private let resolved: ResolvedLogo

    /// Creates a view rendering the given logo spec.
    ///
    /// - Parameters:
    ///   - spec: The stored logo spec string.
    ///   - fallbackSeedText: Seed text used to derive an `avatar:` spec's colors/initials when the
    ///     spec itself doesn't carry a `text` param (e.g. an app name to keep the avatar in sync as
    ///     it changes).
    public init(spec: String, fallbackSeedText: String = "") {
        self.resolved = resolveLogoSpec(spec, fallbackSeedText: fallbackSeedText)
    }

    /// Creates a view rendering an already-resolved logo.
    public init(resolved: ResolvedLogo) {
        self.resolved = resolved
    }

    public var body: some View {
        switch resolved {
        case .emoji(let glyph):
            GeometryReader { proxy in
                Text(glyph)
                    .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.8))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        case .avatar(let spec):
            avatarOrIcon(spec)
        case .url(let urlString):
            remoteImage(urlString)
        }
    }

    @ViewBuilder
    private func avatarOrIcon(_ spec: AvatarSpec) -> some View {
        switch spec.variant {
        case .anonymousAnimal:
            let fallbackSpec = "avatar:variant=anonymous_animal,content=\(spec.content)"
            iconOrFallback(LogoIconCatalog.anonymousAnimalImage(named: spec.content), spec: fallbackSpec)
        case .anonymousEntity:
            let fallbackSpec = "avatar:variant=anonymous_entity,content=\(spec.content)"
            iconOrFallback(LogoIconCatalog.anonymousEntityImage(named: spec.content), spec: fallbackSpec)
        case .oneLetter, .twoLetter:
            AvatarView(spec: spec)
        }
    }

    @ViewBuilder
    private func iconOrFallback(_ image: Image?, spec: String) -> some View {
        if let image {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            remoteImage(spec)
        }
    }

    @ViewBuilder
    private func remoteImage(_ urlString: String) -> some View {
        if let url = URL(string: urlString), url.scheme != nil {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
        } else {
            Color.clear
        }
    }
}
