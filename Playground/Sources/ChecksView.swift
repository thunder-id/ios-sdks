// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

struct ChecksView: View {
    @EnvironmentObject private var state: ThunderIDState
    @EnvironmentObject private var checks: ChecksModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    if let notice {
                        NoticeBanner(text: notice)
                    }
                    SummaryCard()
                    EndpointsCard(config: checks.config)
                    ForEach(CapabilityCatalog.sections) { section in
                        VStack(spacing: 8) {
                            SectionLabel(text: section.name)
                            VStack(spacing: 0) {
                                ForEach(section.items) { capability in
                                    CheckRow(capability: capability, status: checks.status(capability.id)) {
                                        Task { await checks.run(capability) }
                                    }
                                    if capability.id != section.items.last?.id {
                                        Divider().overlay(Palette.text(0.06))
                                    }
                                }
                            }
                            .playgroundGroup()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .task { await checks.checkHealth() }
    }

    private var notice: String? {
        if let error = state.error { return "SDK failed to initialize: \(error)" }
        if !checks.config.isLoaded {
            return "Config.plist not found. Copy Config.plist.example to Sources/Config.plist and fill it in."
        }
        return nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            ThunderIDMark(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Playground")
                    .font(.system(size: 17, weight: .semibold))
                Text("ThunderID iOS · SwiftUI")
                    .font(.mono(11.5, weight: .medium))
                    .foregroundColor(Palette.accent)
            }
            Spacer()
            HeaderAvatar()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Palette.primary.opacity(0.10), Palette.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
}

/// The signed-in user's avatar, rendered by the SDK's `UserAvatar`.
private struct HeaderAvatar: View {
    @EnvironmentObject private var state: ThunderIDState

    var body: some View {
        if state.isSignedIn {
            UserAvatar(size: 40)
        } else {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 22))
                .foregroundColor(Palette.text(0.5))
                .frame(width: 40, height: 40)
                .background(Palette.text(0.06))
                .clipShape(Circle())
                .accessibilityLabel("Signed out")
        }
    }
}

private struct SummaryCard: View {
    @EnvironmentObject private var checks: ChecksModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ProgressRing(fraction: Double(checks.passCount) / Double(max(checks.total, 1)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(checks.passCount) of \(checks.total) passing")
                        .font(.system(size: 15))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(healthColor)
                            .frame(width: 7, height: 7)
                        Text(checks.healthLabel)
                            .font(.mono(11.5, weight: .medium))
                            .foregroundColor(Palette.text(0.55))
                            .lineLimit(1)
                    }
                    .onTapGesture { Task { await checks.checkHealth() } }
                }
                Spacer(minLength: 0)
            }
            Button {
                Task { await checks.runAll() }
            } label: {
                HStack(spacing: 8) {
                    if checks.isRunningAll {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13))
                    }
                    Text(checks.isRunningAll ? "Running checks" : "Run all checks")
                        .font(.system(size: 14.5, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Palette.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(checks.isRunningAll)
        }
        .playgroundCard()
    }

    private var healthColor: Color {
        switch checks.health {
        case .healthy: return Palette.success
        case .unreachable: return Palette.danger
        case .unknown, .checking: return Palette.idle
        }
    }
}

struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.text(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Palette.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .combine)
    }
}

private struct CheckRow: View {
    let capability: Capability
    let status: CheckStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StatusIcon(status: status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(capability.name)
                        .font(.system(size: 14))
                        .foregroundColor(Palette.text(0.92))
                    Text(capability.api)
                        .font(.mono(11))
                        .foregroundColor(Palette.text(0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let note = status.note {
                        Text(note)
                            .font(.system(size: 11.5))
                            .foregroundColor(noteColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if capability.isAvailable {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(Palette.text(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status.isRunning || !capability.isAvailable)
        .accessibilityLabel("\(capability.name). \(status.note ?? "")")
    }

    private var noteColor: Color {
        switch status {
        case .fail: return Palette.dangerText
        case .pass: return Palette.successText
        case .unavailable: return Palette.warningText
        case .idle, .running: return Palette.text(0.5)
        }
    }
}

struct StatusIcon: View {
    let status: CheckStatus

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14))
            if status.isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Palette.link)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(foreground)
            }
        }
        .frame(width: 26, height: 26)
    }

    private var symbol: String {
        switch status {
        case .pass: return "checkmark"
        case .fail: return "xmark"
        case .unavailable: return "nosign"
        case .idle, .running: return "minus"
        }
    }

    private var tint: Color {
        switch status {
        case .pass: return Palette.success
        case .fail: return Palette.danger
        case .running: return Palette.primary
        case .unavailable: return Palette.warning
        case .idle: return Palette.idle
        }
    }

    private var foreground: Color {
        switch status {
        case .pass: return Palette.successText
        case .fail: return Palette.dangerText
        case .running: return Palette.link
        case .unavailable: return Palette.warningText
        case .idle: return Palette.text(0.55)
        }
    }
}

struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(Palette.warningText)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(Palette.text(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Where `baseUrl` (sign-in, tokens, flows) and each management collection resolve to.
/// Collapsed to one line until tapped, or open from the start with `-showEndpoints YES`.
private struct EndpointsCard: View {
    let config: PlaygroundConfig
    @State private var isExpanded = UserDefaults.standard.bool(forKey: "showEndpoints")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.accent)
                    Text(
                        config.hasEndpointOverrides
                            ? "Management endpoints overridden"
                            : "Management endpoints on the base URL"
                    )
                        .font(.system(size: 13.5, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.text(0.4))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                row(name: "baseUrl", url: config.baseUrl, source: "baseUrl")
                ForEach(config.resolvedEndpoints) { endpoint in
                    row(
                        name: endpoint.collection.path,
                        url: endpoint.url,
                        source: endpoint.source.rawValue,
                        isDefault: endpoint.source == .baseUrl
                    )
                }
                Text("Override with THUNDERID_ENDPOINT_* in Config.plist.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.text(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .playgroundGroup()
    }

    private func row(name: String, url: String, source: String, isDefault: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.mono(11.5, weight: .medium))
                    .foregroundColor(Palette.accent)
                Spacer()
                Text(source)
                    .font(.mono(10.5))
                    .foregroundColor(isDefault ? Palette.text(0.4) : Palette.warningText)
            }
            Text(url)
                .font(.mono(11))
                .foregroundColor(Palette.text(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
