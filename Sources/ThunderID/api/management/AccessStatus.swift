// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An identity's effective access status, with precedence ``suspended`` over ``locked`` over ``active``.
/// Applications are never ``locked``. A status this SDK does not know keeps its raw value.
public struct AccessStatusValue: RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let active = AccessStatusValue(rawValue: "ACTIVE")
    public static let locked = AccessStatusValue(rawValue: "LOCKED")
    public static let suspended = AccessStatusValue(rawValue: "SUSPENDED")
}

/// What put an identity into the status it reports. A reason this SDK does not know keeps its raw value.
public struct AccessHoldReason: RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let administrativeSuspension = AccessHoldReason(rawValue: "ADMINISTRATIVE_SUSPENSION")
    /// A suspension carried from the identity this one depends on, such as a personal agent's owner.
    public static let cascadedSuspension = AccessHoldReason(rawValue: "CASCADED_SUSPENSION")
    public static let failedAttempts = AccessHoldReason(rawValue: "FAILED_ATTEMPTS")
    /// A suspension the identity's owner placed, such as the owner of a personal agent.
    public static let ownerSuspension = AccessHoldReason(rawValue: "OWNER_SUSPENSION")
    public static let suspensionReleaseLock = AccessHoldReason(rawValue: "SUSPENSION_RELEASE_LOCK")
}

/// Who placed a suspension: the organization, the identity's owner (such as the owner of an agent), or
/// ``cascade`` for one carried from the identity it depends on, such as a personal agent's owner, while
/// that identity is suspended. Each suspension is independent and is lifted only by whoever placed it. A
/// party this SDK does not know keeps its raw value.
public struct SuspensionAppliedBy: RawRepresentable, Codable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let cascade = SuspensionAppliedBy(rawValue: "cascade")
    public static let organization = SuspensionAppliedBy(rawValue: "organization")
    public static let owner = SuspensionAppliedBy(rawValue: "owner")
}

/// One live automatic lock: the authentication method it holds, and when it lifts.
public struct AccessLockedMethod: Codable, Equatable {
    /// The authentication method the lock holds, or `account` for all of them.
    public let method: String
    /// When the lock lifts on its own. `nil` when it lasts until released.
    public let expiresAt: String?
}

/// What a management read says about a status beyond its value.
public struct AccessStatusDetails: Codable, Equatable {
    public let reason: AccessHoldReason?
    /// When an administrative hold was placed. `nil` for an automatic lock.
    public let since: String?
    /// The operator's note on an administrative hold. Show it as plain text.
    public let operatorNote: String?
    /// Who placed each suspension in force. Present only when the status is ``AccessStatusValue/suspended``,
    /// and only for an identity that more than the organization can suspend, such as a personal agent.
    /// `nil` means the organization's.
    public let appliedBy: [SuspensionAppliedBy]?
    /// Every live automatic lock. `nil` for a status that is not a lock.
    public let lockedMethods: [AccessLockedMethod]?
}

/// The access status a management read of a user or an agent carries. The server computes it on read
/// and never accepts it on a write.
public struct AccessStatus: Codable, Equatable {
    public let value: AccessStatusValue
    /// What produced the status. `nil` when there is nothing to add.
    public let details: AccessStatusDetails?

    public init(value: AccessStatusValue, details: AccessStatusDetails? = nil) {
        self.value = value
        self.details = details
    }

    /// Who holds the identity suspended, from ``AccessStatusDetails/appliedBy``. Empty unless the status is
    /// ``AccessStatusValue/suspended``.
    public var suspendedBy: [SuspensionAppliedBy] {
        value == .suspended ? details?.appliedBy ?? [] : []
    }
}

public extension ApplicationAccessStatus {
    /// The status as an ``AccessStatusValue``, or `nil` when the server reported none.
    var accessStatus: AccessStatusValue? {
        value.map { AccessStatusValue(rawValue: $0.uppercased()) }
    }
}
