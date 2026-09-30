// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import os
import ThunderID

private let logger = Logger(subsystem: "dev.thunderid.sdk", category: "Flow")

private func containsUserSelect(_ component: FlowComponent) -> Bool {
    component.type == "USER_SELECT" || (component.components ?? []).contains(where: containsUserSelect)
}

/// Sign-in and sign-up do not render `USER_SELECT`: listing users needs a signed-in user's token,
/// which does not exist yet. Logs one warning when a step carries one.
func warnIfUserSelectSkipped(inputs: [FlowInput], components: [FlowComponent]) {
    guard inputs.contains(where: { $0.type == "USER_SELECT" }) || components.contains(where: containsUserSelect) else {
        return
    }
    logger.warning("USER_SELECT is only supported where a signed-in user's token is available; skipping it")
}
