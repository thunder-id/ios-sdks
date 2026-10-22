// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import ThunderIDSwiftUI

struct ExplorerView: View {
    enum SheetTab: Hashable {
        case controls
        case code
    }

    @EnvironmentObject private var checks: ChecksModel
    @EnvironmentObject private var log: EventLog
    @EnvironmentObject private var ids: ManagementIds
    /// `-component groupMembers` (any component ID) as a launch argument opens that component.
    @State private var selectedId = UserDefaults.standard.string(forKey: "component") ?? "signInButton"
    @State private var storyId = ""
    @State private var values: [String: PropValues] = [:]
    @State private var isDark = true
    @State private var sheetTab: SheetTab = .controls
    @State private var events: [String] = []

    private var components: [ComponentSpec] {
        ExplorerCatalog.components(
            applicationId: checks.config.applicationId ?? "",
            ids: AdminStoryIds(
                groupId: ids.groupId ?? "",
                roleId: ids.roleId ?? "",
                userId: ids.userId ?? "",
                agentId: ids.agentId ?? ""
            )
        )
    }

    private var spec: ComponentSpec {
        components.first { $0.id == selectedId } ?? components[0]
    }

    private var groupNames: [String] {
        components.map(\.group).reduce(into: []) { names, group in
            if !names.contains(group) { names.append(group) }
        }
    }

    private var current: PropValues { values[spec.id] ?? spec.defaults }

    var body: some View {
        VStack(spacing: 0) {
            header
            storyChips
            preview
            sheet
        }
    }

    // MARK: - Header and stories

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.group)
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.text(0.5))
                Menu {
                    // Grouped, since the admin components roughly double the list.
                    ForEach(groupNames, id: \.self) { group in
                        Section(group) {
                            ForEach(components.filter { $0.group == group }) { component in
                                Button(component.name) { select(component) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(spec.name)
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.2)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.6)
                    }
                    .foregroundColor(.white)
                }
                .accessibilityLabel("Component \(spec.name)")
            }
            Spacer()
            Button {
                isDark.toggle()
            } label: {
                Image(systemName: isDark ? "moon" : "sun.max")
                    .font(.system(size: 17))
                    .foregroundColor(Palette.text(0.8))
                    .frame(width: 44, height: 44)
                    .background(Palette.text(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle preview theme")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var storyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(spec.stories) { story in
                    let isOn = story.id == activeStoryId
                    Button {
                        apply(story)
                    } label: {
                        Text(story.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isOn ? Palette.link : Palette.text(0.7))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(isOn ? Palette.primary.opacity(0.2) : Palette.text(0.04))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isOn ? Palette.primary.opacity(0.5) : Palette.text(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    private var activeStoryId: String {
        storyId.isEmpty ? spec.stories.first?.id ?? "" : storyId
    }

    // MARK: - Preview

    private var preview: some View {
        ScrollView {
            ComponentPreview(spec: spec, values: current) { event in
                events.append(event)
                log.record("component:\(event)", spec.name)
            }
            .frame(maxWidth: .infinity, minHeight: spec.isTall ? 260 : 190)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 34)
        }
        .frame(height: spec.isTall ? 330 : 250)
        .background(PreviewBackground(isDark: isDark))
        .environment(\.colorScheme, isDark ? .dark : .light)
        .overlay(alignment: .bottom) {
            HStack {
                if !events.isEmpty {
                    Text("\(events.last ?? "") × \(events.count)")
                        .font(.mono(11, weight: .medium))
                        .foregroundColor(Palette.link)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Palette.primary.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Spacer()
                Text(isDark ? "dark" : "light")
                    .font(.mono(11, weight: .medium))
                    .foregroundColor(isDark ? Palette.text(0.45) : Color.black.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.text(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Bottom sheet

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Palette.text(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)
            SegmentedPicker(options: [(SheetTab.controls, "Controls"), (SheetTab.code, "Code")], selection: $sheetTab)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)
            ScrollView {
                if sheetTab == .controls {
                    ControlsPanel(controls: spec.controls, values: binding)
                } else {
                    CodePanel(code: spec.snippet(current))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            Palette.sheet
                .clipShape(RoundedCorners(radius: 20))
                .shadow(color: .black.opacity(0.35), radius: 16, y: -8)
        )
        .overlay(alignment: .top) {
            RoundedCorners(radius: 20)
                .stroke(Palette.text(0.1), lineWidth: 1)
                .mask(Rectangle().frame(height: 20).frame(maxHeight: .infinity, alignment: .top))
        }
        .padding(.top, -14)
    }

    private var binding: Binding<PropValues> {
        Binding(
            get: { current },
            set: { values[spec.id] = $0 }
        )
    }

    private func select(_ component: ComponentSpec) {
        selectedId = component.id
        storyId = ""
        events = []
    }

    private func apply(_ story: Story) {
        storyId = story.id
        values[spec.id] = current.merging(story.preset) { _, preset in preset }
    }
}

/// Dotted canvas behind the preview, in the preview's color scheme.
private struct PreviewBackground: View {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            let dot = isDark ? Color.white.opacity(0.08) : Color(hex: 0x0F172A, opacity: 0.12)
            var xPos: CGFloat = 8
            while xPos < size.width {
                var yPos: CGFloat = 8
                while yPos < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: xPos, y: yPos, width: 1.5, height: 1.5)), with: .color(dot))
                    yPos += 16
                }
                xPos += 16
            }
        }
        .background(isDark ? Color(hex: 0x071022) : Color(hex: 0xEEF1F6))
    }
}

/// Rounds only the top corners, for the bottom sheet.
struct RoundedCorners: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
