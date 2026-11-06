// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// The organization unit switcher's stories: the dropdown on sample units, paged inside its menu, the
/// connected one on the signed-in user's units, and a custom render drawn as a segmented picker.
extension ExplorerCatalog {
    static let organization: [ComponentSpec] = [
        ComponentSpec(
            id: "organizationUnitSwitcher",
            name: "OrganizationUnitSwitcher",
            group: "Organization",
            defaults: ["source": "sample", "scope": "all", "render": "built-in", "limit": "20"],
            controls: [
                StoryControl(name: "source", kind: .options(["sample", "live"])),
                StoryControl(name: "scope", kind: .options(["all", "siblings"])),
                StoryControl(name: "render", kind: .options(["built-in", "custom"])),
                StoryControl(name: "limit", kind: .options(["20", "2"]))
            ],
            stories: [
                Story(id: "sample", name: "Sample", preset: ["source": "sample", "render": "built-in", "limit": "20"]),
                Story(id: "paged", name: "Paged", preset: ["source": "sample", "render": "built-in", "limit": "2"]),
                Story(id: "live", name: "Signed-in user", preset: ["source": "live", "render": "built-in"]),
                Story(id: "custom", name: "Custom rendering", preset: ["source": "sample", "render": "custom"])
            ]
        ) { values in
            let scope = values.text("scope") == "siblings" ? "scope: .siblings" : ""
            let paging = "limit: 2, offset: offset, totalResults: units.count, onPageChange: { offset = $0 }"
            let base = values.text("limit") == "2"
                ? "BaseOrganizationUnitSwitcher(units: page, currentId: current, \(paging)) { unit in /* switch */ }"
                : "BaseOrganizationUnitSwitcher(units: units, currentId: current) { unit in /* switch */ }"
            let head = values.text("source") == "live" ? "OrganizationUnitSwitcher(\(scope))" : base
            guard values.text("render") == "custom" else { return head }
            return """
            OrganizationUnitSwitcher(\(scope)) { switcher in
                Picker("Organization", selection: Binding(
                    get: { switcher.currentId ?? "" },
                    set: { id in switcher.units.first { $0.id == id }.map(switcher.onSwitch) }
                )) {
                    ForEach(switcher.units) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }
            """
        }
    ]
}

struct OrganizationUnitSwitcherPreview: View {
    @EnvironmentObject private var state: ThunderIDState
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var offset = 0

    private static let units = [
        AccessibleOrganizationUnit(id: "ou-east", handle: "acme/east", name: "Acme East"),
        AccessibleOrganizationUnit(id: "ou-west", handle: "acme/west", name: "Acme West"),
        AccessibleOrganizationUnit(id: "ou-north", handle: "acme/north", name: "Acme North")
    ]

    var body: some View {
        if values.text("source") == "live" {
            if state.isSignedIn {
                live
            } else {
                PreviewHint(text: "Sign in to list the units the signed-in user can access.")
            }
        } else if values.text("render") == "custom" {
            BaseOrganizationUnitSwitcher(
                units: Self.units,
                currentId: "ou-east",
                onSwitch: { onEvent("onSwitch \($0.handle)") },
                content: { SegmentedSwitcher(switcher: $0) }
            )
        } else if values.text("limit") == "2" {
            BaseOrganizationUnitSwitcher(
                units: Array(Self.units.dropFirst(offset).prefix(2)),
                currentId: "ou-east",
                currentName: "Acme East",
                limit: 2,
                offset: offset,
                totalResults: Self.units.count,
                onPageChange: { page in
                    offset = page
                    onEvent("onPageChange \(page)")
                },
                onSwitch: { onEvent("onSwitch \($0.handle)") }
            )
        } else {
            BaseOrganizationUnitSwitcher(units: Self.units, currentId: "ou-east") { onEvent("onSwitch \($0.handle)") }
        }
    }

    @ViewBuilder private var live: some View {
        let scope: AccessibleOrganizationUnitScope? = values.text("scope") == "siblings" ? .siblings : nil
        if values.text("render") == "custom" {
            OrganizationUnitSwitcher(
                scope: scope,
                onSwitched: { _ in onEvent("onSwitched") },
                content: { SegmentedSwitcher(switcher: $0) }
            )
        } else {
            OrganizationUnitSwitcher(
                scope: scope,
                onSwitched: { _ in onEvent("onSwitched") },
                onSignInRequired: { unit, _ in onEvent("onSignInRequired \(unit.handle)") }
            )
        }
    }
}

/// A custom render: the units as a segmented picker.
private struct SegmentedSwitcher: View {
    let switcher: OrganizationUnitSwitcherState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Organization", selection: selection) {
                ForEach(switcher.units) { unit in
                    Text(unit.name).tag(unit.id)
                }
            }
            .pickerStyle(.segmented)
            if switcher.isLoading { ProgressView() }
            if let error = switcher.error {
                Text(error).foregroundColor(.red)
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { switcher.switchingId ?? switcher.currentId ?? "" },
            set: { id in
                if let unit = switcher.units.first(where: { $0.id == id }) { switcher.onSwitch(unit) }
            }
        )
    }
}
