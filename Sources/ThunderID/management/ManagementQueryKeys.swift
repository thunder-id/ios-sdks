// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Cache keys for management resources. The SwiftUI wrappers use them to refetch after a mutation,
/// and an application can reuse them as keys in its own cache.
public enum ApplicationQueryKeys {
    public static let application = "application"
    public static let applications = "applications"
}

/// Cache keys for user resources.
public enum UserQueryKeys {
    public static let user = "user"
    public static let users = "users"
}

/// Cache keys for agent resources.
public enum AgentQueryKeys {
    public static let agent = "agent"
    public static let agents = "agents"
}
