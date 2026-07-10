import SwiftUI

/// Three-column workspace with native split dividers.
struct StudioPanelSplitView: View {
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag

    var body: some View {
        HSplitView {
            if layout.showAxisTree {
                axisTreeColumn
                    .registerPanelFrame(AxisTreePanelFrameKey.self) { frame in
                        editor.workspaceDrag.setAxisTreeFrame(frame)
                    }
                    .workspaceDropZoneHighlight(
                        isActive: workspaceDrag.shouldHighlightAxisTreePanel,
                        tint: StudioColors.dropNewProject
                    )
            }

            if layout.showInstances {
                InstanceListPanel()
                    .frame(
                        minWidth: StudioPanelMetrics.instancesMin,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .registerPanelFrame(InstancesPanelFrameKey.self) { frame in
                        editor.workspaceDrag.setInstancesFrame(frame)
                    }
                    .workspaceDropZoneHighlight(
                        isActive: workspaceDrag.shouldHighlightInstancesPanel,
                        tint: StudioColors.dropNewProject
                    )
            }

            if layout.showInspector {
                InspectorColumn()
                    .frame(
                        minWidth: StudioPanelMetrics.inspectorMin,
                        idealWidth: layout.inspectorWidth,
                        maxWidth: inspectorMaxWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .modifier(
                        TrackResizableWidth(
                            range: StudioPanelMetrics.inspectorMin...StudioPanelMetrics.inspectorMax,
                            storedWidth: $layout.inspectorWidth
                        )
                    )
                    .registerPanelFrame(InspectorPanelFrameKey.self) { frame in
                        editor.workspaceDrag.setInspectorPanelFrame(frame)
                    }
                    .workspaceDropZoneHighlight(
                        isActive: workspaceDrag.shouldHighlightInspectorPanel(
                            activeProjectID: editor.activeProjectID
                        ),
                        tint: StudioColors.dropAddExisting
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(layout.panelVisibilityToken)
    }

    // MARK: - Axis tree column

    @ViewBuilder
    private var axisTreeColumn: some View {
        if layout.axisTreeCollapsed {
            AxisTreeRail {
                withAnimation(.easeOut(duration: 0.18)) {
                    layout.axisTreeCollapsed = false
                }
            }
            .frame(width: StudioPanelMetrics.axisTreeRailWidth)
            .frame(maxHeight: .infinity)
            .background(.bar)
            .zIndex(1)
        } else {
            AxisTreePanel()
                .frame(
                    minWidth: StudioPanelMetrics.axisTreeMin,
                    idealWidth: layout.axisTreeWidth,
                    maxWidth: axisTreeMaxWidth,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .modifier(
                    TrackResizableWidth(
                        range: StudioPanelMetrics.axisTreeMin...StudioPanelMetrics.axisTreeMax,
                        storedWidth: $layout.axisTreeWidth
                    )
                )
        }
    }

    private var axisTreeMaxWidth: CGFloat? {
        let onlyColumn = layout.showAxisTree && !layout.showInstances && !layout.showInspector
        return onlyColumn ? nil : StudioPanelMetrics.axisTreeMax
    }

    private var inspectorMaxWidth: CGFloat? {
        layout.showInspector && !layout.showInstances ? nil : StudioPanelMetrics.inspectorMax
    }
}

private extension View {
    func registerPanelFrame<K: PreferenceKey>(
        _ key: K.Type,
        onChange: @escaping (CGRect) -> Void
    ) -> some View where K.Value == CGRect {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: key,
                    value: geometry.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(key) { frame in
            onChange(frame)
        }
    }
}

private struct TrackResizableWidth: ViewModifier {
    let range: ClosedRange<CGFloat>
    @Binding var storedWidth: CGFloat

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { persist(geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, width in
                        persist(width)
                    }
            }
        }
    }

    private func persist(_ width: CGFloat) {
        let clamped = min(max(width, range.lowerBound), range.upperBound)
        guard abs(storedWidth - clamped) > 0.5 else { return }
        storedWidth = clamped
    }
}

// MARK: - Collapsed rail

private struct AxisTreeRail: View {
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StudioPanelHeaderChrome {
                Button(action: onExpand) {
                    Image(systemName: "sidebar.left")
                        .font(StudioTypography.bodyMedium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show axis tree")
            }

            StudioSectionLabel(title: "Axis tree")
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(
                    width: StudioPanelMetrics.axisTreeRailWidth,
                    height: StudioPanelMetrics.axisTreeRailLabelHeight,
                    alignment: .center
                )
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

enum StudioPanelMetrics {
    static let axisTreeMin: CGFloat = 280
    static let axisTreeDefault: CGFloat = 320
    static let axisTreeMax: CGFloat = 420
    static let axisTreeRailWidth: CGFloat = 44
    /// Unrotated width of `StudioSectionLabel("Axis tree")` — reserved as layout height after −90° rotation.
    static let axisTreeRailLabelHeight: CGFloat = 54

    static let instancesMin: CGFloat = 320

    static let inspectorMin: CGFloat = 260
    static let inspectorDefault: CGFloat = 300
    static let inspectorMax: CGFloat = 480
}
