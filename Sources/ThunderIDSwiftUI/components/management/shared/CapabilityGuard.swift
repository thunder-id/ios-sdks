// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// One management action: `action` (`view` by default) on `resource` (`app`, `user`, ...).
public struct CapabilityRequirement: Equatable {
    public let resource: String
    public let action: String

    public init(_ resource: String, _ action: String = "view") {
        self.resource = resource
        self.action = action
    }
}

/// Renders `content` only when the signed-in user may perform an action, or any one of several, as the
/// server's capabilities report it. It is unstyled, and renders nothing in its place unless given a
/// fallback: `denied` when the user may not, `loading` while the capabilities load, and `error` when they
/// cannot be read.
///
/// It decides what to show, not what is allowed: the server still authorizes every request.
///
/// ```swift
/// CapabilityGuard(resource: "app", action: "create", denied: AnyView(Text("Not allowed"))) {
///     ApplicationCreate()
/// }
/// ```
public struct CapabilityGuard<Content: View>: View {
    @EnvironmentObject private var state: ThunderIDState
    private let anyOf: [CapabilityRequirement]
    private let denied: AnyView?
    private let loading: AnyView?
    private let error: AnyView?
    private let content: Content

    /// Guards on `action` on `resource`.
    public init(
        resource: String,
        action: String = "view",
        denied: AnyView? = nil,
        loading: AnyView? = nil,
        error: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            anyOf: [CapabilityRequirement(resource, action)],
            denied: denied,
            loading: loading,
            error: error,
            content: content
        )
    }

    /// Guards on any one of `anyOf`.
    public init(
        anyOf: [CapabilityRequirement],
        denied: AnyView? = nil,
        loading: AnyView? = nil,
        error: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.anyOf = anyOf
        self.denied = denied
        self.loading = loading
        self.error = error
        self.content = content()
    }

    public var body: some View {
        CapabilityGuardBody(store: state.capabilities, guarded: self)
    }

    /// What the guard shows for the state of `store`.
    func phase(_ store: CapabilitiesState) -> CapabilityGuardPhase {
        if store.isLoading { return .loading }
        if store.error != nil { return .error }
        return anyOf.contains { store.can($0.resource, $0.action) } ? .allowed : .denied
    }

    fileprivate func render(_ store: CapabilitiesState) -> AnyView? {
        switch phase(store) {
        case .loading: return loading
        case .error: return error
        case .allowed: return AnyView(content)
        case .denied: return denied
        }
    }
}

enum CapabilityGuardPhase: Equatable {
    case loading, error, allowed, denied
}

private struct CapabilityGuardBody<Content: View>: View {
    @ObservedObject var store: CapabilitiesState
    let guarded: CapabilityGuard<Content>

    var body: some View {
        // The zero-size view keeps the read starting even when nothing else renders.
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .task { store.load() }
            if let view = guarded.render(store) { view }
        }
    }
}
