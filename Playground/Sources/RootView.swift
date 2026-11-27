// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

enum PlaygroundTab: String, CaseIterable {
    case checks = "Checks"
    case components = "Components"
    case session = "Session"
    case logs = "Logs"

    var systemImage: String {
        switch self {
        case .checks: return "checkmark.circle"
        case .components: return "square.grid.2x2"
        case .session: return "key"
        case .logs: return "list.bullet"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var checks: ChecksModel
    @EnvironmentObject private var log: EventLog
    @State private var tab: PlaygroundTab = Self.initialTab

    /// `-tab Session` (or any tab name) as a launch argument opens that tab, for screenshots.
    private static var initialTab: PlaygroundTab {
        let name = UserDefaults.standard.string(forKey: "tab") ?? ""
        return PlaygroundTab(rawValue: name) ?? .checks
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PlaygroundTabBar(selection: $tab)
        }
        .background(Palette.background.ignoresSafeArea())
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .task { checks.bind(state) }
        .onChange(of: state.isInitialized) { initialized in
            // `-runAll YES` as a launch argument runs every automatic check once the SDK is up.
            guard initialized, UserDefaults.standard.bool(forKey: "runAll") else { return }
            Task { await checks.runAll() }
        }
        .onChange(of: state.isInitialized) { initialized in
            guard initialized else { return }
            if let error = state.error {
                log.record("sdk:initFailed", error, kind: .error)
            } else {
                log.record("sdk:initialized", state.isSignedIn ? "session restored" : "signed out", kind: .success)
            }
        }
        .onChange(of: state.user?.sub) { sub in
            log.record("state:user", sub.map { "sub=\($0)" } ?? "signed out")
        }
        .sheet(isPresented: $checks.isNativeSignInPresented, onDismiss: checks.cancelNativeSignIn) {
            NativeSignInSheet()
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .checks: ChecksView().telemetryScreen("checks")
        case .components: ExplorerView().telemetryScreen("components")
        case .session: SessionView().telemetryScreen("session")
        case .logs: LogsView().telemetryScreen("logs")
        }
    }
}

struct PlaygroundTabBar: View {
    @Binding var selection: PlaygroundTab

    var body: some View {
        HStack {
            ForEach(PlaygroundTab.allCases, id: \.self) { tab in
                let isOn = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .regular))
                            .frame(height: 24)
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isOn ? Palette.link : Palette.text(0.55))
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(
            Palette.tabBar.opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.text(0.08))
                .frame(height: 1)
        }
    }
}

/// Hosts the SDK's `SignIn` component for the app-native sign-in check.
struct NativeSignInSheet: View {
    @EnvironmentObject private var checks: ChecksModel

    var body: some View {
        NavigationStack {
            ScrollView {
                SignIn(
                    applicationId: checks.config.applicationId ?? "",
                    onComplete: { Task { await checks.finishNativeSignIn(error: nil) } },
                    onError: { message in Task { await checks.finishNativeSignIn(error: message) } }
                )
                .padding(20)
            }
            .navigationTitle("App-native sign-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { checks.isNativeSignInPresented = false }
                }
            }
        }
    }
}
