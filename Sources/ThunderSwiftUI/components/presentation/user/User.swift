import SwiftUI
import ThunderID

/// Read-only display of the current user (spec §8.4 Presentation).
public struct UserObject: View {
    @EnvironmentObject private var state: ThunderState
    @EnvironmentObject private var i18n: ThunderI18n

    public init() {}

    public var body: some View {
        BaseUserObject { user in
            Text(user?.displayName ?? user?.username ?? i18n.resolve("user.anonymous"))
                .accessibilityLabel(user?.displayName ?? i18n.resolve("user.anonymous"))
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseUserObject<Content: View>: View {
    @EnvironmentObject private var state: ThunderState
    public let content: (User?) -> Content

    public init(@ViewBuilder content: @escaping (User?) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(state.user)
    }
}
