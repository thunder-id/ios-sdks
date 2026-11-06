// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// Reactive wrappers over the project and organization unit operations. Each accepts an optional
/// `fetcher` that takes precedence over `ThunderIDConfig.http.fetcher`. Only the Control Plane serves
/// projects.
public extension ThunderIDState {
    // MARK: - Projects

    func projectsQuery(limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<ProjectListResponse> {
        let client = client
        return query(key: listKey(ProjectQueryKeys.projects, ["limit": limit, "offset": offset])) {
            try await client.projects.list(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func projectQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<Project> {
        let client = client
        return query(key: [ProjectQueryKeys.project, id]) {
            try await client.projects.get(id: id, fetcher: fetcher)
        }
    }

    func createProjectMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<CreateProjectRequest, Project> {
        let client = client
        return mutation(
            invalidating: { _ in [[ProjectQueryKeys.projects], [OrganizationUnitQueryKeys.organizationUnits]] },
            perform: { request in try await client.projects.create(request, fetcher: fetcher) }
        )
    }

    /// Updates a project, and the current project too when it is the one updated.
    func updateProjectMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: UpdateProjectRequest), Project> {
        let client = client
        return mutation(
            invalidating: { [[ProjectQueryKeys.project, $0.id], [ProjectQueryKeys.projects]] },
            perform: { [weak self] input in
                let project = try await client.projects.update(id: input.id, input.request, fetcher: fetcher)
                if self?.currentProject?.id == project.id { self?.setCurrentProject(project) }
                return project
            }
        )
    }

    /// Deletes a project, and clears the current project when it is the one deleted.
    func deleteProjectMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[ProjectQueryKeys.projects], [OrganizationUnitQueryKeys.organizationUnits]] },
            perform: { [weak self] id in
                try await client.projects.delete(id: id, fetcher: fetcher)
                if self?.currentProject?.id == id { self?.setCurrentProject(nil) }
            }
        )
    }

    // MARK: - Organization units

    /// The root organization units, or the units directly beneath `parentId`.
    func organizationUnitsQuery(
        parentId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<OrganizationUnitListResponse> {
        let client = client
        let key = listKey(OrganizationUnitQueryKeys.organizationUnits, ["limit": limit, "offset": offset])
            + ["parent=\(parentId ?? "")"]
        return query(key: key) {
            if let parentId {
                return try await client.organizationUnits.children(
                    .id(parentId),
                    limit: limit,
                    offset: offset,
                    fetcher: fetcher
                )
            }
            return try await client.organizationUnits.list(limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func organizationUnitQuery(id: String, fetcher: ThunderIDFetcher? = nil) -> ResourceQuery<OrganizationUnit> {
        let client = client
        return query(key: [OrganizationUnitQueryKeys.organizationUnit, id]) {
            try await client.organizationUnits.get(id: id, fetcher: fetcher)
        }
    }

    func organizationUnitUsersQuery(id: String, limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<OrganizationUnitUserListResponse> {
        let client = client
        return query(key: memberKey(id, "users", limit, offset)) {
            try await client.organizationUnits.users(.id(id), limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func organizationUnitGroupsQuery(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil,
        fetcher: ThunderIDFetcher? = nil
    ) -> ResourceQuery<OrganizationUnitGroupListResponse> {
        let client = client
        return query(key: memberKey(id, "groups", limit, offset)) {
            try await client.organizationUnits.groups(.id(id), limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func organizationUnitRolesQuery(id: String, limit: Int? = nil, offset: Int? = nil, fetcher: ThunderIDFetcher? = nil)
        -> ResourceQuery<OrganizationUnitRoleListResponse> {
        let client = client
        return query(key: memberKey(id, "roles", limit, offset)) {
            try await client.organizationUnits.roles(.id(id), limit: limit, offset: offset, fetcher: fetcher)
        }
    }

    func createOrganizationUnitMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<OrganizationUnitRequest, OrganizationUnit> {
        let client = client
        return mutation(
            invalidating: { _ in [[OrganizationUnitQueryKeys.organizationUnits]] },
            perform: { request in try await client.organizationUnits.create(request, fetcher: fetcher) }
        )
    }

    func updateOrganizationUnitMutation(fetcher: ThunderIDFetcher? = nil)
        -> ResourceMutation<(id: String, request: OrganizationUnitRequest), OrganizationUnit> {
        let client = client
        return mutation(
            invalidating: {
                [[OrganizationUnitQueryKeys.organizationUnit, $0.id], [OrganizationUnitQueryKeys.organizationUnits]]
            },
            perform: { input in
                try await client.organizationUnits.update(id: input.id, input.request, fetcher: fetcher)
            }
        )
    }

    func deleteOrganizationUnitMutation(fetcher: ThunderIDFetcher? = nil) -> ResourceMutation<String, Void> {
        let client = client
        return mutation(
            invalidating: { _ in [[OrganizationUnitQueryKeys.organizationUnits]] },
            perform: { id in try await client.organizationUnits.delete(id: id, fetcher: fetcher) }
        )
    }
}

private extension ThunderIDState {
    func memberKey(_ id: String, _ kind: String, _ limit: Int?, _ offset: Int?) -> [String] {
        [OrganizationUnitQueryKeys.organizationUnitMembers, id, kind]
            + listKey("", ["limit": limit, "offset": offset]).dropFirst()
    }
}
