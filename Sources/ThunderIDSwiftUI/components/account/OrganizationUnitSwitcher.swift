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
    /// The current unit's name, from the page or the session, or `nil` when it is not known.
    public let currentName: String?
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

extension OrganizationUnitSwitcherState {
    /// The name of `currentId` on the page, or `fallback` when the page does not list it.
    static func name(of currentId: String?, in units: [AccessibleOrganizationUnit], fallback: String?) -> String? {
        units.first { $0.id == currentId }?.name ?? fallback
    }

    /// What the field shows: the unit being switched to, the current unit, or the loading or placeholder text.
    func fieldText(_ i18n: ThunderIDI18n) -> String {
        if let switchingId {
            let name = units.first { $0.id == switchingId }?.name ?? switchingId
            return i18n.resolve("organizationUnitSwitcher.switching", ["name": name])
        }
        if let currentName { return currentName }
        return i18n.resolve(isLoading ? "organizationUnitSwitcher.loading" : "organizationUnitSwitcher.placeholder")
    }

    /// Picks `unit` from the menu: another unit switches to it, the current one only closes the menu.
    func choose(_ unit: AccessibleOrganizationUnit) {
        guard unit.id != currentId else { return }
        onSwitch(unit)
    }

    /// Whether the menu pages: there are more units than the page size.
    var isPaged: Bool { onPageChange != nil && totalResults > limit }
    var hasPreviousPage: Bool { offset > 0 }
    var hasNextPage: Bool { offset + limit < totalResults }
}

/// A field showing the current organization unit under a small label, rendered from the data it is given.
/// Tapping it opens a menu of the units, each with its handle and the current one checked; picking another
/// calls `onSwitch`.
public struct BaseOrganizationUnitSwitcher<Content: View>: View {
    @EnvironmentObject private var i18n: ThunderIDI18n
    let renderState: OrganizationUnitSwitcherState
    let content: ((OrganizationUnitSwitcherState) -> Content)?

    init(state: OrganizationUnitSwitcherState, renderContent: ((OrganizationUnitSwitcherState) -> Content)?) {
        self.renderState = state
        self.content = renderContent
    }

    /// - Parameters:
    ///   - currentName: Names the current unit when `units` does not list it, such as the session's unit.
    ///   - content: Renders custom UI in place of the default view, from the units, the current one, the
    ///     loading, switching and error state, the paging, and `onSwitch`.
    public init(
        units: [AccessibleOrganizationUnit],
        currentId: String?,
        currentName: String? = nil,
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
                currentName: OrganizationUnitSwitcherState.name(of: currentId, in: units, fallback: currentName),
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

    private var label: String { i18n.resolve("organizationUnitSwitcher.label") }

    private var defaultBody: some View {
        let state = renderState
        return VStack(alignment: .leading, spacing: 4) {
            Menu {
                menuItems(state)
            } label: {
                field(state)
            }
            .disabled(state.switchingId != nil)
            .accessibilityLabel(label.isEmpty ? i18n.resolve("organizationUnitSwitcher.placeholder") : label)
            .accessibilityValue(state.fieldText(i18n))
            .accessibilityIdentifier("thunderid-organization-unit-switcher-field")
            if let error = state.error {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .accessibilityIdentifier("thunderid-organization-unit-switcher-error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thunderid-organization-unit-switcher")
    }

    /// The label above the current unit's name, with a chevron, or progress while a switch runs.
    private func field(_ state: OrganizationUnitSwitcherState) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(state.fieldText(i18n))
                    .foregroundColor(state.currentName == nil && state.switchingId == nil ? .secondary : .primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if state.switchingId != nil {
                ProgressView().accessibilityHidden(true)
            } else {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func menuItems(_ state: OrganizationUnitSwitcherState) -> some View {
        if state.isLoading {
            Text(i18n.resolve("organizationUnitSwitcher.loading"))
        } else if state.units.isEmpty {
            Text(state.error ?? i18n.resolve("organizationUnitSwitcher.empty"))
        } else {
            ForEach(state.units) { unit in
                option(unit, state: state)
            }
        }
        if let onPageChange = state.onPageChange, state.isPaged {
            Section {
                Button(i18n.resolve("organizationUnitSwitcher.previous")) {
                    onPageChange(max(state.offset - state.limit, 0))
                }
                .disabled(!state.hasPreviousPage || state.isLoading)
                Button(i18n.resolve("organizationUnitSwitcher.next")) {
                    onPageChange(state.offset + state.limit)
                }
                .disabled(!state.hasNextPage || state.isLoading)
            }
        }
    }

    /// A unit in the menu: its name, its handle as secondary text, and a check on the current one.
    private func option(_ unit: AccessibleOrganizationUnit, state: OrganizationUnitSwitcherState) -> some View {
        let isCurrent = unit.id == state.currentId
        return Button {
            state.choose(unit)
        } label: {
            Text(unit.name)
            Text(unit.handle)
            if isCurrent {
                Image(systemName: "checkmark").foregroundColor(.accentColor)
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("thunderid-organization-unit-\(unit.id)")
    }
}

public extension BaseOrganizationUnitSwitcher where Content == EmptyView {
    init(
        units: [AccessibleOrganizationUnit],
        currentId: String?,
        currentName: String? = nil,
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
                currentName: OrganizationUnitSwitcherState.name(of: currentId, in: units, fallback: currentName),
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

/// The current organization unit in a field that opens a menu of the units the signed-in user can access
/// (`GET /users/me/ous`). Picking another switches the session to it with
/// ``ThunderIDClient/switchOrganizationUnit(_:options:)`` and refreshes the signed-in user; on failure the
/// session stays as it was and a translated message is shown. `onSelect` lets the app take over the choice.
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
        let units = model.list?.organizationUnits ?? []
        return OrganizationUnitSwitcherState(
            units: units,
            currentId: model.currentId,
            currentName: OrganizationUnitSwitcherState.name(
                of: model.currentId,
                in: units,
                fallback: model.sessionName
            ),
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
    /// The unit the session is issued for, from its claims.
    @Published private(set) var sessionUnit: CurrentOrganizationUnit?

    /// The unit the session is in: the list's, or the session's until the list loads.
    var currentId: String? { list.flatMap { $0.current.isEmpty ? nil : $0.current } ?? sessionUnit?.id }
    /// The session unit's name, when it is the current unit. It names the field when the page does not list it.
    var sessionName: String? { sessionUnit?.id == currentId ? sessionUnit?.name : nil }

    func load(client: ThunderIDClient, props: OrganizationUnitSwitcherProps, i18n: ThunderIDI18n, offset: Int) async {
        isLoading = true
        defer { isLoading = false }
        sessionUnit = try? await client.getCurrentOrganizationUnit()
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
        guard switchingId == nil, unit.id != currentId else { return }
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
