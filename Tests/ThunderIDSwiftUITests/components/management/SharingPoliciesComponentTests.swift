// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the sharing policies component, built in and through a custom render.
@MainActor
final class SharingPoliciesComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "sharing_policies_component_tests_locale")

    private final class Captured<Value> {
        var value: Value?
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func render(_ view: some View) {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let renderer = ImageRenderer(
            content: view
                .environmentObject(i18n)
                .environmentObject(state)
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    private func policies() throws -> [SharingPolicy] {
        try decode(
            #"[{"id":"pol-1","initiatingOuId":"ou-root","stage":"share","version":2,"# +
            #""childUnits":{"mode":"all","excludedOuIds":["ou-9"]}},"# +
            #"{"id":"pol-2","stage":"reshare","isReadOnly":true,"# +
            #""childUnits":{"mode":"selected","units":[{"ouId":"ou-2","reach":"subtree"},{"ouId":"ou-3","reach":"unit"}]},"# +
            #""otherTreeRoots":{"mode":"selected","units":[{"ouId":"tree-2"}]}},"# +
            #"{"id":"pol-3","allUnits":{}}]"#
        )
    }

    private func overlay() throws -> ResolvedOverlay {
        try decode(
            #"{"ouId":"ou-2","isOwnedByOU":false,"visible":true,"policyIds":["pol-2"],"# +
            #""rules":{"email":{"editable":true},"locale":{"editable":false,"allowedValues":["en","fr"]}}}"#
        )
    }

    func testScopesAreDescribedAsTheServerRecordsThem() throws {
        let rows = try policies()
        XCTAssertEqual(SharingScope.describe(rows[0], i18n: i18n), "All units beneath the issuer, except ou-9")
        XCTAssertEqual(
            SharingScope.describe(rows[1], i18n: i18n),
            "Chosen units: ou-2 and the units beneath it, ou-3 · Other trees: tree-2"
        )
        XCTAssertEqual(SharingScope.describe(rows[2], i18n: i18n), "All organization units")
    }

    func testTheFormBuildsTheReachBeneathTheIssuer() throws {
        var draft = SharingPolicyDraft(policy: nil)
        XCTAssertEqual(draft.mode, .allChildren)
        draft.excluded = "ou-9, "
        XCTAssertEqual(draft.childUnits, .all(excluding: ["ou-9"]))
        draft.mode = .selected
        XCTAssertFalse(draft.isValid)
        draft.units = " ou-2 ,ou-3"
        draft.subtree = true
        XCTAssertEqual(
            draft.childUnits,
            .selected([SharingChildUnit(ouId: "ou-2", reach: "subtree"), SharingChildUnit(ouId: "ou-3", reach: "subtree")])
        )
        let everywhere = SharingPolicyDraft(policy: try policies()[2])
        XCTAssertEqual(everywhere.mode, .everywhere)
        XCTAssertNil(everywhere.childUnits)
        XCTAssertEqual(everywhere.allUnits, SharingAllUnits(excludedOuIds: nil))
    }

    func testDataChangingActionsAreOffUnlessEnabled() {
        XCTAssertFalse(SharingPolicies(resourceType: .user, resourceId: "u-1").editable)
        XCTAssertNil(BaseSharingPolicies(policies: []).onCreate)
    }

    // MARK: - Built-in UI

    func testBaseComponentRendersStandalone() throws {
        render(
            BaseSharingPolicies(
                policies: try policies(),
                totalResults: 30,
                onPageChange: { _ in },
                overlay: try overlay(),
                onCreate: { _ in },
                onUpdate: { _, _ in },
                onDelete: { _ in }
            )
        )
        render(BaseSharingPolicies(policies: [], isLoading: true))
        render(BaseSharingPolicies(policies: [], error: "Could not load the sharing policies. Please try again."))
    }

    func testConnectedComponentRendersWithoutAServer() {
        for type in SharingResourceType.allCases {
            render(SharingPolicies(resourceType: type, resourceId: "r-1", ouId: "ou-1", editable: true))
        }
    }

    // MARK: - Custom render

    func testContentGetsThePoliciesOverlayAndActionsOnlyWhenEditable() throws {
        let editable = Captured<SharingPoliciesState>()
        let readOnly = Captured<SharingPoliciesState>()
        var created: [SharingPolicyRequest] = []
        var deleted: [String] = []
        var updated: [Int] = []

        render(
            BaseSharingPolicies(
                policies: try policies(),
                overlay: try overlay(),
                onCreate: { created.append($0) },
                onUpdate: { _, request in updated.append(request.version) },
                onDelete: { deleted.append($0.id ?? "") }
            ) { sharing in
                let _ = (editable.value = sharing)
                Text("")
            }
        )
        render(
            BaseSharingPolicies(policies: try policies()) { sharing in
                let _ = (readOnly.value = sharing)
                Text("")
            }
        )

        let sharing = try XCTUnwrap(editable.value)
        XCTAssertEqual(sharing.policies.count, 3)
        XCTAssertEqual(sharing.totalResults, 3)
        XCTAssertEqual(sharing.overlay?.rules?["locale"]?.allowedValues, ["en", "fr"])
        XCTAssertEqual(sharing.scope(of: sharing.policies[2]), "All organization units")
        sharing.onCreate?(SharingPolicyRequest(childUnits: .all()))
        sharing.onUpdate?(sharing.policies[0], SharingPolicyUpdateRequest(version: 2, childUnits: .all()))
        sharing.onDelete?(sharing.policies[0])
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(updated, [2])
        XCTAssertEqual(deleted, ["pol-1"])
        let viewOnly = try XCTUnwrap(readOnly.value)
        XCTAssertNil(viewOnly.onCreate)
        XCTAssertNil(viewOnly.onUpdate)
        XCTAssertNil(viewOnly.onDelete)
        XCTAssertNil(viewOnly.overlay)
    }
}
