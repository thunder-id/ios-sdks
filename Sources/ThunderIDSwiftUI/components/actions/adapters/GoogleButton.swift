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

/// "Continue with Google" federated sign-in trigger, styled to match the outlined action
/// buttons rendered below a SignIn form's "Or" divider.
struct GoogleButton: View {
    let label: String
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        TriggerButtonStyle(label: label, isLoading: isLoading, onTap: onTap) {
            GoogleGlyph()
                .frame(width: 18, height: 18)
        }
    }
}

/// Multi-color Google "G" glyph, ported from the SVG path data used by the web SDK's
/// `GoogleButton` icon adapter (viewBox 67.91 x 67.901).
private struct GoogleGlyph: View {
    private static let viewBox = CGSize(width: 67.91, height: 67.901)

    var body: some View {
        ZStack {
            SVGIconPath(
                pathData: "M15.049,160.965l-2.364,8.824-8.639.183a34.011,34.011,0,0,1-.25-31.7h0l7.691,1.41," +
                    "3.369,7.645a20.262,20.262,0,0,0,.19,13.642Z",
                viewBox: Self.viewBox,
                translate: CGSize(width: 0, height: -119.93)
            )
            .fill(Color(red: 0.984, green: 0.733, blue: 0))

            SVGIconPath(
                pathData: "M294.24,208.176A33.939,33.939,0,0,1,282.137,241h0l-9.687-.494-1.371-8.559a20.235," +
                    "20.235,0,0,0,8.706-10.333H261.628V208.176Z",
                viewBox: Self.viewBox,
                translate: CGSize(width: -226.93, height: -180.567)
            )
            .fill(Color(red: 0.318, green: 0.559, blue: 0.973))

            SVGIconPath(
                pathData: "M81.668,328.8h0a33.962,33.962,0,0,1-51.161-10.387l11-9.006a20.192,20.192,0,0,0,29.1,10.338Z",
                viewBox: Self.viewBox,
                translate: CGSize(width: -26.463, height: -268.374)
            )
            .fill(Color(red: 0.157, green: 0.706, blue: 0.275))

            SVGIconPath(
                pathData: "M80.451,7.816l-11,9A20.19,20.19,0,0,0,39.686,27.393l-11.06-9.055h0A33.959,33.959,0," +
                    "0,1,80.451,7.816Z",
                viewBox: Self.viewBox,
                translate: CGSize(width: -24.828, height: 0)
            )
            .fill(Color(red: 0.945, green: 0.263, blue: 0.212))
        }
    }
}
