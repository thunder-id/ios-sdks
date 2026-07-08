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
import ThunderIDSwiftUI

@main
struct ThunderIDB2CApp: App {
    private let config: ThunderIDConfig = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            fatalError(
                "Config.plist not found — copy Config.plist.example to Sources/Config.plist and fill in your values"
            )
        }
        return ThunderIDConfig(
            baseUrl: dict["THUNDERID_BASE_URL"] ?? "",
            clientId: dict["THUNDERID_CLIENT_ID"],
            scopes: ["openid", "profile", "email"],
            afterSignInUrl: dict["THUNDERID_AFTER_SIGN_IN_URL"],
            afterSignOutUrl: dict["THUNDERID_AFTER_SIGN_OUT_URL"],
            applicationId: dict["THUNDERID_APPLICATION_ID"]
        )
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .thunderIDProvider(config: config)
                .tint(Color(red: 0.212, green: 0.533, blue: 1.0))
        }
    }
}
