import SwiftUI

/// Renders `content` only when the user is NOT authenticated (spec §8.4 Guards).
public struct SignedOut<Content: View, Fallback: View>: View {
    @EnvironmentObject private var state: ThunderState
    private let content: Content
    private let fallback: Fallback

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder fallback: () -> Fallback
    ) {
        self.content = content()
        self.fallback = fallback()
    }

    public var body: some View {
        if !state.isSignedIn {
            content
        } else {
            fallback
        }
    }
}

public extension SignedOut where Fallback == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content) { EmptyView() }
    }
}
