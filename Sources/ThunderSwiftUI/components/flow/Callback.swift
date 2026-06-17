import SwiftUI

/// Handles the OAuth2 redirect callback URL after a browser-based flow (spec §8.4 Flow).
///
/// Pass the callback URL received via onOpenURL / deep link to `url`.
public struct Callback: View {
    @EnvironmentObject private var state: ThunderState
    @EnvironmentObject private var i18n: ThunderI18n
    public let url: URL
    public let onComplete: (() -> Void)?
    public let onError: ((String) -> Void)?

    public init(url: URL, onComplete: (() -> Void)? = nil, onError: ((String) -> Void)? = nil) {
        self.url = url
        self.onComplete = onComplete
        self.onError = onError
    }

    public var body: some View {
        BaseCallback(url: url) { result in
            switch result {
            case .success:
                Task { await state.refresh() }
                onComplete?()
            case .failure(let error):
                onError?(error.localizedDescription)
            }
        } content: { isLoading, error in
            VStack(spacing: 8) {
                if isLoading {
                    Text(i18n.resolve("callback.loading"))
                } else if let error {
                    Text(error)
                }
            }
        }
    }
}

/// Unstyled base variant (spec §8.3).
public struct BaseCallback<Content: View>: View {
    @EnvironmentObject private var state: ThunderState
    public let url: URL
    public let onResult: (Result<Void, Error>) -> Void
    public let content: (Bool, String?) -> Content

    @State private var isLoading = true
    @State private var error: String?

    public init(
        url: URL,
        onResult: @escaping (Result<Void, Error>) -> Void,
        @ViewBuilder content: @escaping (Bool, String?) -> Content
    ) {
        self.url = url
        self.onResult = onResult
        self.content = content
    }

    public var body: some View {
        content(isLoading, error)
            .task {
                do {
                    _ = try await state.client.handleRedirectCallback(url: url)
                    isLoading = false
                    onResult(.success(()))
                } catch {
                    let msg = error.localizedDescription
                    self.error = msg
                    isLoading = false
                    onResult(.failure(error))
                }
            }
    }
}
