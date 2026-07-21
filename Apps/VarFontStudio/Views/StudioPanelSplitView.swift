import SwiftUI

/// Three-column workspace with native split dividers.
struct StudioPanelSplitView: View {
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    @State private var namesHeaderMeta: NameTableHeaderMeta?

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
                middleColumn
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

    // MARK: - Middle column (Instances | Names)

    private var middleColumn: some View {
        VStack(spacing: 0) {
            StudioPanelHeader(
                title: middlePanelTitle,
                horizontalPadding: StudioSpacing.panelHorizontal
            ) {
                middleHeaderMeta
            }

            middleScopeSwitcher
                .padding(.horizontal, StudioSpacing.panelHorizontal)
                .frame(height: StudioChromeBand.scope)

            Divider()

            Group {
                switch editor.inspectorFocus.middlePanelScope {
                case .instances:
                    InstanceListPanel(showsPanelHeader: false)
                case .names:
                    NameTablePanel(showsPanelHeader: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(NameTableHeaderMetaKey.self) { meta in
                namesHeaderMeta = meta
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var middlePanelTitle: String {
        switch editor.inspectorFocus.middlePanelScope {
        case .instances: "Instances"
        case .names: "Names"
        }
    }

    @ViewBuilder
    private var middleHeaderMeta: some View {
        switch editor.inspectorFocus.middlePanelScope {
        case .instances:
            InstanceListPanel.headerCounts(editor: editor)
        case .names:
            if let meta = namesHeaderMeta {
                HStack(spacing: 3) {
                    Text("\(meta.populated)")
                        .foregroundStyle(StudioColors.computedHighlight)
                    Text("populated")
                        .foregroundStyle(.secondary)
                    if meta.missing > 0 {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text("\(meta.missing)")
                            .foregroundStyle(.secondary)
                        Text("missing")
                            .foregroundStyle(.secondary)
                    }
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("Win 3/1/409")
                        .foregroundStyle(.tertiary)
                }
                .font(StudioTypography.meta)
            }
        }
    }

    private var middleScopeSwitcher: some View {
        HStack(spacing: 2) {
            middleScopeButton(title: "Instances", scope: .instances)
            middleScopeButton(title: "Names", scope: .names)
        }
    }

    private func middleScopeButton(title: String, scope: MiddlePanelScope) -> some View {
        let isOn = editor.inspectorFocus.middlePanelScope == scope
        return Button {
            if scope == .names {
                editor.inspectorFocus.showNamesPanel()
            } else {
                editor.inspectorFocus.middlePanelScope = .instances
            }
        } label: {
            Text(title)
                .font(StudioTypography.meta)
                .fontWeight(isOn ? .semibold : .regular)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, StudioSpacing.panelVertical)
                .background {
                    RoundedRectangle(cornerRadius: StudioRadius.row)
                        .fill(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: StudioRadius.row)
                                .strokeBorder(
                                    isOn ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.22),
                                    lineWidth: 1
                                )
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: StudioRadius.row))
        }
        .buttonStyle(.plain)
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
                .padding(.top, StudioSpace.x2)

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
    /// Snapped up from measured ~54 onto the 4pt lattice.
    static let axisTreeRailLabelHeight: CGFloat = StudioSpace.unit * 14 // 56

    static let instancesMin: CGFloat = 320

    static let inspectorMin: CGFloat = 260
    static let inspectorDefault: CGFloat = 300
    static let inspectorMax: CGFloat = 480
}
