// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import os
import ThunderID

private let logger = Logger(subsystem: "dev.thunderid.sdk", category: "Flow")

/// The picker input types. Listing their options needs a signed-in user's token, so sign-in and sign-up skip them.
let pagedSelectInputTypes: Set<String> = ["USER_SELECT", "AUTH_FLOW_SELECT", "USER_TYPE_SELECT"]

private func containsPagedSelect(_ component: FlowComponent) -> Bool {
    pagedSelectInputTypes.contains(component.type ?? "")
        || (component.components ?? []).contains(where: containsPagedSelect)
}

/// Sign-in and sign-up do not render the picker inputs: listing their options needs a signed-in user's token,
/// which does not exist yet. Logs one warning when a step carries one.
func warnIfPagedSelectSkipped(inputs: [FlowInput], components: [FlowComponent]) {
    guard inputs.contains(where: { pagedSelectInputTypes.contains($0.type ?? "") })
        || components.contains(where: containsPagedSelect) else {
        return
    }
    logger.warning(
        "USER_SELECT, AUTH_FLOW_SELECT and USER_TYPE_SELECT need a signed-in user's token; skipping them"
    )
}
