import SwiftUI
import ThunderSwiftUI

@main
struct ThunderB2CApp: App {
    private let config: ThunderIDConfig = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            fatalError("Config.plist not found — copy Config.plist.example to Sources/Config.plist and fill in your values")
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
                .tint(Color(red: 1.0, green: 0.353, blue: 0.373))
        }
    }
}
