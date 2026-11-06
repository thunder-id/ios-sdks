// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
@testable import ThunderID
import XCTest
@testable import ThunderIDSwiftUI

/// Covers the project components, built in and through a custom render.
@MainActor
final class ProjectComponentTests: XCTestCase {
    private let i18n = ThunderIDI18n(language: "en-US", storageKey: "project_component_tests_locale")

    private final class Captured<Value> {
        var value: Value?
    }

    private func render(_ view: some View, state: ThunderIDState? = nil) {
        let state = state ?? ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let renderer = ImageRenderer(
            content: view
                .environmentObject(i18n)
                .environmentObject(state)
                .frame(width: 400)
        )
        XCTAssertNotNil(renderer.cgImage)
    }

    private func projects() throws -> [Project] {
        try JSONDecoder().decode(
            [Project].self,
            from: Data(
                (#"[{"id":"p-1","handle":"shop","displayName":"Online shop","description":"Shop","# +
                    #""createdAt":"2026-01-02T03:04:05Z"},{"id":"p-2","handle":"default","displayName":"Default"}]"#)
                    .utf8
            )
        )
    }

    // MARK: - Defaults

    func testDataChangingActionsAreOffUnlessEnabled() {
        XCTAssertFalse(ProjectDetails(projectId: "p-1").editable)
        XCTAssertFalse(ProjectDetails(projectId: "p-1").deletable)
        XCTAssertNil(BaseProjectDetails(project: nil).onDelete)
        XCTAssertNil(BaseProjectDetails(project: nil).onUpdate)
    }

    func testHandlesFollowTheServerRule() {
        XCTAssertTrue(AdminHandle.isValid("online-shop_2"))
        XCTAssertFalse(AdminHandle.isValid("Online"))
        XCTAssertFalse(AdminHandle.isValid("-shop"))
        XCTAssertFalse(AdminHandle.isValid("shop-"))
        XCTAssertFalse(AdminHandle.isValid(""))
        XCTAssertFalse(AdminHandle.isValid(String(repeating: "a", count: 101)))
    }

    func testServerRefusalsAreTranslatedByCode() {
        let projects = AdminHierarchyErrors.projectKeys
        XCTAssertEqual(projects["PRJ-1006"], "admin.projects.errors.id_conflict")
        XCTAssertEqual(projects["PRJ-1012"], "admin.projects.errors.handle_conflict")
        XCTAssertEqual(projects["PRJ-1007"], "admin.projects.errors.handle_immutable")
        XCTAssertEqual(projects.count, 3)
        let units = AdminHierarchyErrors.organizationUnitKeys
        XCTAssertEqual(units["OU-1004"], "admin.organization_units.errors.name_conflict")
        XCTAssertEqual(units["OU-1008"], "admin.organization_units.errors.handle_conflict")
        XCTAssertEqual(units["OU-1012"], "admin.organization_units.errors.declarative")
        let deletes = AdminHierarchyErrors.organizationUnitDeleteKeys
        XCTAssertEqual(deletes["OU-1006"], "admin.organization_units.details.delete.has_children")
        XCTAssertEqual(deletes["OU-1012"], "admin.organization_units.errors.declarative")
        XCTAssertEqual(
            i18n.resolve("admin.projects.errors.handle_conflict"),
            "A project with this handle already exists."
        )
        XCTAssertEqual(i18n.resolve("admin.projects.errors.handle_immutable"), "A project's handle cannot be changed.")
    }

    func testProjectDeleteHasNoRefusalMessagesOfItsOwn() {
        let handleTaken = ThunderIDError(code: .invalidInput, message: "x", serverError: ServerError(code: "PRJ-1012"))
        XCTAssertEqual(
            i18n.managementErrorMessage(handleTaken, fallbackKey: "admin.projects.details.delete.error"),
            "Could not delete the project. Please try again."
        )
        let forbidden = ThunderIDError(code: .forbidden, message: "x")
        XCTAssertEqual(
            i18n.managementErrorMessage(forbidden, fallbackKey: "admin.projects.details.delete.error"),
            "You do not have permission to do this."
        )
    }

    // MARK: - Built-in UI

    func testBaseComponentsRenderStandalone() throws {
        let rows = try projects()
        render(BaseProjectList(projects: rows, totalResults: 30, onPageChange: { _ in }, onSelect: { _ in }))
        render(BaseProjectList(projects: [], isLoading: true))
        render(BaseProjectList(projects: [], error: "Could not load projects. Please try again."))
        render(BaseProjectCreate(isSubmitting: true, onCancel: {}, onSubmit: { _ in }))
        render(BaseProjectCreate(error: "A project with this handle or name already exists.") { _ in })
        render(BaseProjectDetails(project: rows[0], onUpdate: { _ in }, onDelete: {}))
        render(BaseProjectDetails(project: nil, isLoading: true))
        render(BaseProjectDetails(project: nil))
        render(BaseProjectSwitcher(projects: rows, currentId: "p-1", onClear: {}) { _ in })
    }

    func testConnectedComponentsRenderWithoutAServer() {
        render(ProjectList())
        render(ProjectCreate())
        render(ProjectDetails(projectId: "p-1", editable: true, deletable: true))
        render(ProjectSwitcher())
    }

    // MARK: - Custom render

    func testListContentReceivesRowsAndSelection() throws {
        let captured = Captured<AdminListState<Project>>()
        var selected: [String] = []

        render(
            BaseProjectList(
                projects: try projects(),
                limit: 2,
                totalResults: 9,
                selectedProjectId: "p-2",
                onPageChange: { _ in },
                onSelect: { selected.append($0.id) }
            ) { list in
                let _ = (captured.value = list)
                Text("\(list.rows.count)")
            }
        )

        let list = try XCTUnwrap(captured.value)
        XCTAssertEqual(list.rows.map(\.handle), ["shop", "default"])
        XCTAssertEqual(list.totalResults, 9)
        XCTAssertEqual(list.selectedId, "p-2")
        list.onSelect?(list.rows[0])
        XCTAssertEqual(selected, ["p-1"])
    }

    func testCreateContentDoesNotSubmitInvalidValues() throws {
        let captured = Captured<ProjectFormState>()
        var submissions: [CreateProjectRequest] = []

        render(
            BaseProjectCreate(onSubmit: { submissions.append($0) }) { form in
                let _ = (captured.value = form)
                TextField("Handle", text: form.handle)
            }
        )

        let form = try XCTUnwrap(captured.value)
        XCTAssertFalse(form.isValid)
        form.submit()
        XCTAssertTrue(submissions.isEmpty)
    }

    func testDetailsContentGetsTheProjectAndOnlyTheAllowedActions() throws {
        let editable = Captured<ProjectDetailsState>()
        let readOnly = Captured<ProjectDetailsState>()
        var deletes = 0
        var updates: [UpdateProjectRequest] = []
        let project = try projects()[0]

        render(
            BaseProjectDetails(
                project: project,
                isDeleting: true,
                onUpdate: { updates.append($0) },
                onDelete: { deletes += 1 }
            ) { details in
                let _ = (editable.value = details)
                Text(details.project?.displayName ?? "")
            }
        )
        render(
            BaseProjectDetails(project: project) { details in
                let _ = (readOnly.value = details)
                Text("")
            }
        )

        let details = try XCTUnwrap(editable.value)
        XCTAssertEqual(details.project?.handle, "shop")
        XCTAssertTrue(details.isDeleting)
        details.onDelete?()
        details.onUpdate?(UpdateProjectRequest(displayName: "Shop", handle: "shop"))
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(updates.first?.displayName, "Shop")
        XCTAssertNil(readOnly.value?.onDelete)
        XCTAssertNil(readOnly.value?.onUpdate)
    }

    func testSwitcherContentMarksTheCurrentProjectAndSelects() throws {
        let captured = Captured<ProjectSwitcherState>()
        var selected: [String] = []

        render(
            BaseProjectSwitcher(projects: try projects(), currentId: "p-2", onSelect: { selected.append($0.id) }) { switcher in
                let _ = (captured.value = switcher)
                Text(switcher.current?.displayName ?? "")
            }
        )

        let switcher = try XCTUnwrap(captured.value)
        XCTAssertEqual(switcher.current?.handle, "default")
        XCTAssertNil(switcher.onClear)
        switcher.onSelect(switcher.projects[0])
        XCTAssertEqual(selected, ["p-1"])
    }

    func testConnectedSwitcherSetsTheCurrentProject() throws {
        let state = ThunderIDState(client: ThunderIDClient(), i18n: i18n)
        let captured = Captured<ProjectSwitcherState>()
        var selected: [String] = []

        render(
            ProjectSwitcher(onSelect: { selected.append($0.id) }) { switcher in
                let _ = (captured.value = switcher)
                Text("")
            },
            state: state
        )

        let switcher = try XCTUnwrap(captured.value)
        XCTAssertNil(switcher.currentId)
        switcher.onSelect(try projects()[0])
        XCTAssertEqual(state.currentProject?.id, "p-1")
        XCTAssertEqual(selected, ["p-1"])
        switcher.onClear?()
        XCTAssertNil(state.currentProject)
    }
}
