import SwiftUI

/// Three-column workspace with native split dividers; inspector auto-hides when nothing is selected.
struct StudioPanelSplitView: View {
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @EnvironmentObject private var editor: EditorViewModel

    private var inspectorHasSelection: Bool {
        editor.inspectorInspectableInstance != nil
    }

    private var inspectorIsVisible: Bool {
        layout.isInspectorPresented(inspectorHasSelection: inspectorHasSelection)
    }

    var body: some View {
        HSplitView {
            if layout.showAxisTree {
                axisTreeColumn
            }

            if layout.showInstances {
                InstanceListPanel()
                    .frame(
                        minWidth: StudioPanelMetrics.instancesMin,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }

            if layout.showInspector, inspectorIsVisible {
                InspectorPanel()
                    .frame(
                        minWidth: StudioPanelMetrics.inspectorMin,
                        idealWidth: layout.inspectorWidth,
                        maxWidth: inspectorMaxWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(layout.panelVisibilityToken)
        .onChange(of: layout.showInspector) { _, isOn in
            if isOn, !inspectorHasSelection, layout.inspectorAutoHide {
                layout.userOpenedInspector()
            }
        }
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
        }
    }

    private var axisTreeMaxWidth: CGFloat? {
        let onlyColumn = layout.showAxisTree && !layout.showInstances && !inspectorIsVisible
        return onlyColumn ? nil : StudioPanelMetrics.axisTreeMax
    }

    private var inspectorMaxWidth: CGFloat? {
        layout.showInspector && !layout.showInstances ? nil : StudioPanelMetrics.inspectorMax
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

    static let projectMenuListWidth: CGFloat = 320
    static let projectMenuNamingWidth: CGFloat = 272
}
