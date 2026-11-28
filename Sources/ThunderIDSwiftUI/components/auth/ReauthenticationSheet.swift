// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderID

/// Signs the signed-in user in again by running the sign-in flow with `maxAge`, for a session from an embedded
/// (app-native) sign-in. The provider shows it as a sheet for ``ReauthenticationRequest``. The flow's session
/// replaces the current one only when the same user signs in; closing the sheet ends the re-sign-in.
struct ReauthenticationSheet: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var i18n: ThunderIDI18n
    let request: ReauthenticationRequest

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(i18n.resolve("reauthentication.description"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    SignIn(
                        applicationId: request.applicationId,
                        reauthentication: SignInReauthentication(maxAge: request.maxAge)
                    ) {
                        state.finishReauthentication(request, .success(()))
                    }
                }
                .padding()
            }
            .navigationTitle(i18n.resolve("reauthentication.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(i18n.resolve("reauthentication.close")) {
                        state.finishReauthentication(request, .failure(ThunderIDState.reauthenticationCancelled))
                    }
                }
            }
        }
    }
}

/// A sign-in flow that signs the signed-in user in again, for a change that needs a more recent sign-in.
struct SignInReauthentication {
    /// How recent, in seconds, the sign-in must be.
    let maxAge: Int?
}

extension SignIn {
    /// Signs the signed-in user in again with the sign-in flow.
    init(applicationId: String, reauthentication: SignInReauthentication, onComplete: @escaping () -> Void) {
        self.init(applicationId: applicationId, onComplete: onComplete)
        self.reauthentication = reauthentication
    }
}

extension BaseSignIn {
    init(
        applicationId: String,
        organizationUnitId: String?,
        reauthentication: SignInReauthentication?,
        onComplete: (() -> Void)?,
        onError: ((String) -> Void)?,
        @ViewBuilder content: @escaping (SignInState) -> Content
    ) {
        self.init(
            applicationId: applicationId,
            organizationUnitId: organizationUnitId,
            onComplete: onComplete,
            onError: onError,
            content: content
        )
        self.reauthentication = reauthentication
    }
}

/// Shows the open ``ReauthenticationRequest`` as a sheet. SwiftUI presents one sheet per view at a time, so
/// the provider and every view that is itself presented as a sheet register here, and only the innermost
/// registered presenter shows the request.
struct ReauthenticationPresenter: ViewModifier {
    @ObservedObject var state: ThunderIDState
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { state.reauthenticationPresenters.append(id) }
            .onDisappear { state.reauthenticationPresenters.removeAll { $0 == id } }
            .sheet(item: request) { request in
                ReauthenticationSheet(request: request)
                    .environmentObject(state)
                    .environmentObject(state.i18n)
            }
    }

    private var request: Binding<ReauthenticationRequest?> {
        Binding(
            get: { state.reauthenticationPresenters.last == id ? state.reauthenticationRequest : nil },
            set: { request in
                // Swiping the sheet away ends the re-sign-in as closing it does.
                if request == nil, state.reauthenticationPresenters.last == id,
                   let open = state.reauthenticationRequest {
                    state.finishReauthentication(open, .failure(ThunderIDState.reauthenticationCancelled))
                }
            }
        )
    }
}

/// ``ReauthenticationPresenter`` for a view presented as a sheet, with the state from the environment.
struct EnvironmentReauthenticationPresenter: ViewModifier {
    @EnvironmentObject private var state: ThunderIDState

    func body(content: Content) -> some View {
        content.modifier(ReauthenticationPresenter(state: state))
    }
}

public extension View {
    /// Lets the sheet that signs the user in again show over this view. Apply it to the content of a sheet or
    /// full-screen cover that shows ``BaseChangeCredential`` or ``BaseUserProfile`` for a session from an
    /// app-native sign-in: SwiftUI shows one sheet per view at a time, so the provider cannot show it there.
    func presentsReauthentication() -> some View {
        modifier(EnvironmentReauthenticationPresenter())
    }
}
