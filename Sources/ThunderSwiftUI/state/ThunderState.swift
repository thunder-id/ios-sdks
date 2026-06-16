import Foundation
import ThunderID

/// Reactive auth state for SwiftUI views. Held as @StateObject in ThunderIDProvider.
@MainActor
public final class ThunderState: ObservableObject {
    @Published public private(set) var user: User?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isInitialized: Bool = false
    @Published public private(set) var error: String?

    public let client: ThunderClient
    public let i18n: ThunderI18n

    public var isSignedIn: Bool { user != nil }

    init(client: ThunderClient, i18n: ThunderI18n) {
        self.client = client
        self.i18n = i18n
    }

    func initialize(config: ThunderIDConfig) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await client.initialize(config: config)
            let signedIn = await (try? client.isSignedIn()) ?? false
            if signedIn {
                user = try? await client.getUser()
            }
            isInitialized = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            isInitialized = true
        }
    }

    /// Refreshes sign-in state (call after signIn/signOut).
    public func refresh() async {
        guard isInitialized else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let signedIn = try await client.isSignedIn()
            user = signedIn ? try await client.getUser() : nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Switches the active UI locale.
    public func setLocale(_ locale: String) {
        i18n.setLocale(locale)
    }
}
