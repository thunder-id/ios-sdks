import SwiftUI

/// Renders `indicator` while the SDK is initializing or mid-operation (spec §8.4 Guards).
public struct Loading<Indicator: View>: View {
    @EnvironmentObject private var state: ThunderState
    private let indicator: Indicator

    public init(@ViewBuilder indicator: () -> Indicator) {
        self.indicator = indicator()
    }

    public var body: some View {
        if state.isLoading {
            indicator
        }
    }
}

public extension Loading where Indicator == ProgressView<EmptyView, EmptyView> {
    init() {
        self.init { ProgressView() }
    }
}
