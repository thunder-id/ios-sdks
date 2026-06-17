import SwiftUI
import ThunderSwiftUI

private enum AuthMode {
    case signIn, signUp
}

struct AuthView: View {
    @EnvironmentObject private var state: ThunderState
    private var applicationId: String { (try? state.client.getConfiguration())?.applicationId ?? "" }
    @State private var mode: AuthMode = .signIn

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 72, height: 72)
                        Image(systemName: "house.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    Text("ACME Booking")
                        .font(.title2).bold()
                    Text("Find your perfect stay")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                .padding(.bottom, 40)

                // ── Mode toggle ───────────────────────────────────────────
                Picker("Auth mode", selection: $mode) {
                    Text("Sign In").tag(AuthMode.signIn)
                    Text("Create Account").tag(AuthMode.signUp)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 28)

                // ── Form ──────────────────────────────────────────────────
                Group {
                    if mode == .signIn {
                        SignIn(applicationId: applicationId)
                    } else {
                        SignUp(applicationId: applicationId)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
    }
}
