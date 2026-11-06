// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// What ``BaseOrganizationUnitSwitcher`` and ``OrganizationUnitSwitcher`` hand their `content` closure.
public struct OrganizationUnitSwitcherState {
    /// The units on the current page.
    public let units: [AccessibleOrganizationUnit]
    /// The unit the session is issued for, when known.
    public let currentId: String?
    public let isLoading: Bool
    /// The unit a switch is in flight to, if any.
    public let switchingId: String?
    /// A translated message, or `nil` when there is nothing to report.
    public let error: String?
    public let limit: Int
    public let offset: Int
    /// The total on the server, or the number of units given when it is unknown.
    public let totalResults: Int
    /// Shows the page that starts at the given offset. `nil` when the list is not paginated.
    public let onPageChange: ((Int) -> Void)?
    /// Switches to a unit (or hands it to the app's `onSelect`).
    public let onSwitch: (AccessibleOrganizationUnit) -> Void

    /// The current unit, when it is on this page.
    public var current: AccessibleOrganizationUnit? { units.first { $0.id == currentId } }
}

/// The organization units the signed-in user can access, rendered from the data it is given, with the
/// current one marked. Choosing another calls `onSwitch`.
public struct BaseOrganizationUnitSwitcher<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let renderState: OrganizationUnitSwitcherState
    let content: ((OrganizationUnitSwitcherState) -> Content)?

    init(state: OrganizationUnitSwitcherState, renderContent: ((OrganizationUnitSwitcherState) -> Content)?) {
        self.renderState = state
        self.content = renderContent
    }

    /// - Parameter content: Renders custom UI in place of the default view, from the units, the current
    ///   one, the loading, switching and error state, the paging, and `onSwitch`.
    public init(
        units: [AccessibleOrganizationUnit],
        currentId: String?,
        isLoading: Bool = false,
        switchingId: String? = nil,
        error: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSwitch: @escaping (AccessibleOrganizationUnit) -> Void,
        @ViewBuilder content: @escaping (OrganizationUnitSwitcherState) -> Content
    ) {
        self.init(
            state: OrganizationUnitSwitcherState(
                units: units,
                currentId: currentId,
                isLoading: isLoading,
                switchingId: switchingId,
                error: error,
                limit: limit,
                offset: offset,
                totalResults: totalResults ?? units.count,
                onPageChange: onPageChange,
                onSwitch: onSwitch
            ),
            renderContent: content
        )
    }

    public var body: some View {
        if let content {
            content(renderState)
        } else {
            defaultBody
        }
    }

    private var defaultBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(i18n.resolve("organizationUnitSwitcher.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let error = renderState.error {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("thunderid-organization-unit-switcher-error")
            }
            if renderState.isLoading && renderState.units.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(i18n.resolve("organizationUnitSwitcher.loading"))
                }
            } else if renderState.units.isEmpty {
                Text(i18n.resolve("organizationUnitSwitcher.empty")).foregroundColor(.secondary)
            } else {
                ForEach(renderState.units) { unit in
                    row(unit)
                }
            }
            pager
        }
        .accessibilityIdentifier("thunderid-organization-unit-switcher")
    }

    private func row(_ unit: AccessibleOrganizationUnit) -> some View {
        let isCurrent = unit.id == renderState.currentId
        let isSwitching = unit.id == renderState.switchingId
        return Button {
            renderState.onSwitch(unit)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.name)
                    Text(unit.handle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isSwitching {
                    ProgressView().accessibilityLabel(i18n.resolve("organizationUnitSwitcher.switching"))
                } else if isCurrent {
                    Text(i18n.resolve("organizationUnitSwitcher.current"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "checkmark")
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || renderState.switchingId != nil)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("thunderid-organization-unit-\(unit.id)")
    }

    @ViewBuilder
    private var pager: some View {
        let state = renderState
        if let onPageChange = state.onPageChange, state.totalResults > state.limit {
            HStack {
                Button(i18n.resolve("organizationUnitSwitcher.previous")) {
                    onPageChange(max(state.offset - state.limit, 0))
                }
                .disabled(state.offset == 0)
                Spacer()
                Button(i18n.resolve("organizationUnitSwitcher.next")) {
                    onPageChange(state.offset + state.limit)
                }
                .disabled(state.offset + state.limit >= state.totalResults)
            }
            .frame(minHeight: 44)
        }
    }
}

public extension BaseOrganizationUnitSwitcher where Content == EmptyView {
    init(
        units: [AccessibleOrganizationUnit],
        currentId: String?,
        isLoading: Bool = false,
        switchingId: String? = nil,
        error: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        totalResults: Int? = nil,
        onPageChange: ((Int) -> Void)? = nil,
        onSwitch: @escaping (AccessibleOrganizationUnit) -> Void
    ) {
        self.init(
            state: OrganizationUnitSwitcherState(
                units: units,
                currentId: currentId,
                isLoading: isLoading,
                switchingId: switchingId,
                error: error,
                limit: limit,
                offset: offset,
                totalResults: totalResults ?? units.count,
                onPageChange: onPageChange,
                onSwitch: onSwitch
            ),
            renderContent: nil
        )
    }
}

/// The organization units the signed-in user can access (`GET /users/me/ous`), with the current one
/// marked. Choosing another switches the session to it with ``ThunderIDClient/switchOrganizationUnit(_:options:)``
/// and refreshes the signed-in user; on failure the session stays as it was and a translated message is
/// shown. `onSelect` lets the app take over the choice instead.
public struct OrganizationUnitSwitcher<Content: View>: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    @StateObject private var model = OrganizationUnitSwitcherModel()
    let props: OrganizationUnitSwitcherProps
    let content: ((OrganizationUnitSwitcherState) -> Content)?

    init(props: OrganizationUnitSwitcherProps, renderContent: ((OrganizationUnitSwitcherState) -> Content)?) {
        self.props = props
        self.content = renderContent
    }

    /// - Parameters:
    ///   - scope: Narrows the list relative to the current unit, such as `.siblings`.
    ///   - limit: The page size.
    ///   - switchOptions: How the switch signs in again, such as the `authorize` handler redirect mode needs.
    ///   - onSelect: Takes over the choice: the component then does not switch itself.
    ///   - onSwitched: Called with the user once the session belongs to the chosen unit.
    ///   - onSignInRequired: App-native mode: called when the unit-bounded sign-in needs the user, so the
    ///     app can show ``SignIn`` with that `organizationUnitId`.
    ///   - content: Renders custom UI in place of the default view. See ``BaseOrganizationUnitSwitcher``.
    public init(
        scope: AccessibleOrganizationUnitScope? = nil,
        limit: Int = 20,
        switchOptions: SwitchOrganizationUnitOptions = .init(),
        onSelect: ((AccessibleOrganizationUnit) -> Void)? = nil,
        onSwitched: ((User) -> Void)? = nil,
        onSignInRequired: ((AccessibleOrganizationUnit, EmbeddedFlowResponse) -> Void)? = nil,
        @ViewBuilder content: @escaping (OrganizationUnitSwitcherState) -> Content
    ) {
        self.init(
            props: OrganizationUnitSwitcherProps(
                scope: scope,
                limit: limit,
                switchOptions: switchOptions,
                onSelect: onSelect,
                onSwitched: onSwitched,
                onSignInRequired: onSignInRequired
            ),
            renderContent: content
        )
    }

    public var body: some View {
        BaseOrganizationUnitSwitcher(state: renderState, renderContent: content)
            .task { await model.load(client: state.client, props: props, i18n: i18n, offset: 0) }
    }

    private var renderState: OrganizationUnitSwitcherState {
        OrganizationUnitSwitcherState(
            units: model.list?.organizationUnits ?? [],
            currentId: model.list?.current,
            isLoading: model.isLoading,
            switchingId: model.switchingId,
            error: model.error,
            limit: props.limit,
            offset: model.offset,
            totalResults: model.list?.totalResults ?? 0,
            onPageChange: { offset in
                Task { await model.load(client: state.client, props: props, i18n: i18n, offset: offset) }
            },
            onSwitch: { unit in
                if let onSelect = props.onSelect {
                    onSelect(unit)
                    return
                }
                Task { await model.switchTo(unit, appState: state, props: props, i18n: i18n) }
            }
        )
    }
}

public extension OrganizationUnitSwitcher where Content == EmptyView {
    init(
        scope: AccessibleOrganizationUnitScope? = nil,
        limit: Int = 20,
        switchOptions: SwitchOrganizationUnitOptions = .init(),
        onSelect: ((AccessibleOrganizationUnit) -> Void)? = nil,
        onSwitched: ((User) -> Void)? = nil,
        onSignInRequired: ((AccessibleOrganizationUnit, EmbeddedFlowResponse) -> Void)? = nil
    ) {
        self.init(
            props: OrganizationUnitSwitcherProps(
                scope: scope,
                limit: limit,
                switchOptions: switchOptions,
                onSelect: onSelect,
                onSwitched: onSwitched,
                onSignInRequired: onSignInRequired
            ),
            renderContent: nil
        )
    }
}

struct OrganizationUnitSwitcherProps {
    let scope: AccessibleOrganizationUnitScope?
    let limit: Int
    let switchOptions: SwitchOrganizationUnitOptions
    let onSelect: ((AccessibleOrganizationUnit) -> Void)?
    let onSwitched: ((User) -> Void)?
    let onSignInRequired: ((AccessibleOrganizationUnit, EmbeddedFlowResponse) -> Void)?
}

/// Loads the accessible units and runs a switch for ``OrganizationUnitSwitcher``.
@MainActor
final class OrganizationUnitSwitcherModel: ObservableObject {
    @Published private(set) var list: AccessibleOrganizationUnitList?
    @Published private(set) var isLoading = false
    @Published private(set) var switchingId: String?
    @Published private(set) var error: String?
    @Published private(set) var offset = 0

    func load(client: ThunderIDClient, props: OrganizationUnitSwitcherProps, i18n: ThunderIDI18n, offset: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            list = try await client.getAccessibleOrganizationUnits(
                scope: props.scope, limit: props.limit, offset: offset
            )
            self.offset = offset
            error = nil
        } catch {
            self.error = i18n.resolve("organizationUnitSwitcher.error.load")
        }
    }

    func switchTo(
        _ unit: AccessibleOrganizationUnit,
        appState: ThunderIDState,
        props: OrganizationUnitSwitcherProps,
        i18n: ThunderIDI18n
    ) async {
        guard switchingId == nil, unit.id != list?.current else { return }
        switchingId = unit.id
        defer { switchingId = nil }
        do {
            switch try await appState.client.switchOrganizationUnit(unit.id, options: props.switchOptions) {
            case .switched(let user):
                self.error = nil
                await appState.refresh()
                props.onSwitched?(user)
                await load(client: appState.client, props: props, i18n: i18n, offset: offset)
            case .signInRequired(let response):
                self.error = i18n.resolve("organizationUnitSwitcher.signInRequired", ["name": unit.name])
                props.onSignInRequired?(unit, response)
            }
        } catch {
            self.error = Self.message(for: error, i18n: i18n)
        }
    }

    /// The translated message for a failed switch. The server's own text is never shown.
    static func message(for error: Error, i18n: ThunderIDI18n) -> String {
        if (error as? ThunderIDError)?.code == .organizationUnitUnavailable {
            return i18n.resolve("organizationUnitSwitcher.error.unavailable")
        }
        return i18n.resolve("organizationUnitSwitcher.error.switch")
    }
}
