// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import ThunderID

/// The signed-in user's management capabilities, shared by every view under one ``ThunderIDProvider``
/// through ``ThunderIDState/capabilities``.
///
/// Nothing is read until a view calls ``load()``; then one read serves every view, and it is read again
/// when the signed-in user, their organization unit or their granted permissions change. Signing out
/// discards it.
///
/// Capabilities decide what to offer, never what is allowed: the server authorizes every management
/// request, and the SDK never skips or blocks one because of them.
@MainActor
public final class CapabilitiesState: ObservableObject {
    /// What the server reported, or `nil` until it has been read.
    @Published public internal(set) var capabilities: Capabilities?
    @Published public private(set) var isLoading = false
    /// Why the last read failed. A failure means the capabilities are unavailable, not that the user
    /// lacks them: ``retry()`` reads them again.
    @Published public private(set) var error: Error?

    private let read: () async throws -> Capabilities
    private let grantedPermissions: () async -> [String]
    /// Who is signed in (user and organization unit), or `nil` while nobody is.
    private var session: [String?]?
    private var used = false
    private var started = false
    /// Bumped by every read and by sign-out, so only the latest read may write the state.
    private var generation = 0
    /// What the current answer, or the read in flight, was taken for.
    private var readKey: [String?]?

    init(
        read: @escaping () async throws -> Capabilities,
        grantedPermissions: @escaping () async -> [String]
    ) {
        self.read = read
        self.grantedPermissions = grantedPermissions
    }

    /// Whether the user may perform `action` (`view` by default) on `resource`. False while the
    /// capabilities load, after a failed read, and for anything the server did not report.
    public func can(_ resource: String, _ action: String = "view") -> Bool {
        capabilities?.can(resource, action) ?? false
    }

    /// What the user may do with one record of `resource`. See ``RecordAccess``.
    public func recordAccess(_ resource: String, isReadOnly: Bool? = nil, isOwnedByOU: Bool? = nil) -> RecordAccess {
        RecordAccess(resource: resource, isReadOnly: isReadOnly, isOwnedByOU: isOwnedByOU) { [self] in can($0, $1) }
    }

    /// Marks the capabilities as used and reads them if they have not been read for this session.
    public func load() {
        used = true
        if session != nil, !started { fetch() }
    }

    /// Reads the capabilities again, for example after a failed read.
    public func retry() {
        if session != nil, !isLoading { fetch() }
    }

    /// Tells the state who is signed in, or `nil` when nobody is.
    func setSession(_ next: [String?]?) {
        session = next
        guard next != nil else {
            generation += 1
            readKey = nil
            started = false
            capabilities = nil
            error = nil
            isLoading = false
            return
        }
        guard used else { return }
        if !started {
            fetch()
        } else {
            Task { await refreshIfChanged() }
        }
    }

    private func key(for session: [String?]?) async -> [String?] {
        (session ?? []) + (await grantedPermissions()).sorted().map(Optional.some)
    }

    private func refreshIfChanged() async {
        let current = generation
        let nextKey = await key(for: session)
        // Something newer started meanwhile, or the answer already belongs to this session and token.
        guard current == generation, session != nil, nextKey != readKey || error != nil else { return }
        fetch(key: nextKey)
    }

    private func fetch(key knownKey: [String?]? = nil) {
        generation += 1
        let current = generation
        let forSession = session
        started = true
        readKey = knownKey
        capabilities = nil
        error = nil
        isLoading = true
        Task {
            if knownKey == nil {
                let computed = await key(for: forSession)
                if current == generation { readKey = computed }
            }
            do {
                let result = try await read()
                guard current == generation else { return }
                capabilities = result
            } catch {
                guard current == generation else { return }
                self.error = error
            }
            isLoading = false
        }
    }
}
