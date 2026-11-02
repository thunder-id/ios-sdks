// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

/// The application stories: the `Base*` view with sample records, or the connected view.
struct ApplicationAdminPreview: View {
    let id: String
    let values: PropValues
    let onEvent: (String) -> Void
    @State private var selected: String?
    @State private var secret: String?

    var body: some View {
        switch id {
        case "applicationList": list
        case "applicationDetails": details
        default: create
        }
    }

    @ViewBuilder private var list: some View {
        if values.isLive {
            ApplicationList(
                limit: values.limit,
                title: values.optional("title"),
                description: values.optional("description"),
                selectedApplicationId: selected
            ) { select($0.id, $0.name) }
        } else {
            BaseApplicationList(
                applications: values.isSampleEmpty ? [] : AdminSamples.applications,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                title: values.optional("title"),
                description: values.optional("description"),
                limit: values.limit,
                totalResults: values.isSampleEmpty ? 0 : AdminSamples.applications.count,
                selectedApplicationId: selected,
                onPageChange: { onEvent("onPageChange: \($0)") },
                onSelect: { select($0.id, $0.name) }
            )
        }
    }

    @ViewBuilder private var details: some View {
        let deletable = values.flag("deletable")
        let lifecycle = values.flag("lifecycleActions")
        if values.isLive {
            ApplicationDetails(
                applicationId: values.text("applicationId"),
                editable: true,
                deletable: deletable,
                secretRegenerable: deletable,
                administrationMode: values.administrationMode,
                lifecycleActions: lifecycle
            ) { onEvent("onDeleted") }
        } else {
            let application = values.isSampleLoading ? nil : AdminSamples.application
            BaseApplicationDetails(
                application: application,
                isLoading: values.isSampleLoading,
                error: values.sampleError,
                clientSecret: secret,
                onSecretDone: { secret = nil },
                onDelete: deletable ? { onEvent("onDelete") } : nil,
                onUpdate: { edit in onEvent("onUpdate: \(edit.name), \(edit.grantTypes.joined(separator: ", "))") },
                onRegenerateSecret: deletable
                    ? {
                        secret = "sample-secret-shown-once"
                        onEvent("onRegenerateSecret")
                    }
                    : nil,
                lifecycleActions: AdminSamples.lifecycleActions(
                    .application,
                    status: application?.status?.accessStatus
                ),
                onLifecycleAction: lifecycle ? { action, _ in onEvent("onLifecycleAction: \(action.rawValue)") } : nil
            )
        }
    }

    @ViewBuilder private var create: some View {
        if values.isLive {
            ApplicationCreate(
                ouId: values.optional("ouId"),
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onCreated: { application in onEvent("onCreated: \(application.id)") }
            )
        } else {
            BaseApplicationCreate(
                error: values.sampleError,
                isSubmitting: values.isSubmitting,
                clientSecret: secret,
                onSecretDone: { secret = nil },
                title: values.optional("title"),
                description: values.optional("description"),
                onCancel: { onEvent("onCancel") },
                onSubmit: { submission in
                    secret = submission.publicClient ? nil : "sample-secret-shown-once"
                    onEvent("onSubmit: \(submission.name) (\(submission.grantTypes.joined(separator: ", ")))")
                }
            )
        }
    }

    private func select(_ id: String, _ name: String) {
        selected = id
        onEvent("onSelect: \(name)")
    }
}
