// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// "Sign In with Passkey" trigger, styled to match the outlined action buttons rendered below
/// a SignIn form's "Or" divider. Used as an icon fallback when the flow response's passkey
/// action carries no `startIcon`/`image`.
struct PasskeyButton: View {
    let label: String
    let isLoading: Bool
    var disabled: Bool = false
    let onTap: () -> Void

    var body: some View {
        TriggerButtonStyle(label: label, isLoading: isLoading, disabled: disabled, onTap: onTap) {
            FingerprintGlyph()
                .frame(width: 18, height: 18)
        }
    }
}

/// Fallback fingerprint glyph, ported from the "fingerprint-pattern" line-art icon (24x24
/// viewBox, `stroke="currentColor" stroke-width="2"`), stroked rather than filled.
private struct FingerprintGlyph: View {
    private static let viewBox = CGSize(width: 24, height: 24)
    private static let pathData = [
        "M12,10a2,2,0,0,0,-2,2c0,1.02,-.1,2.51,-.26,4",
        "M14,13.12c0,2.38,0,6.38,-1,8.88",
        "M17.29,21.02c.12,-.6,.43,-2.3,.5,-3.02",
        "M2,12a10,10,0,0,1,18,-6",
        "M2,16h.01",
        "M21.8,16c.2,-2,.131,-5.354,0,-6",
        "M5,19.5C5.5,18,6,15,6,12a6,6,0,0,1,.34,-2",
        "M8.65,22c.21,-.66,.45,-1.32,.57,-2",
        "M9,6.8a6,6,0,0,1,9,5.2v2"
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.pathData.enumerated()), id: \.offset) { _, data in
                SVGIconPath(pathData: data, viewBox: Self.viewBox)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
