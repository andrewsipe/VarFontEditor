import SwiftUI
import VarFontCore

struct ProjectTabAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ProjectMenuTabRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ProjectToolbar: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    @Binding var openMenuProjectID: String?

    private var isSplitHoverTarget: Bool {
        workspaceDrag.hoveredTarget == .newProject
    }

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(editor.openProjects) { openProject in
                        ProjectTabChip(
                            openProject: openProject,
                            openMenuProjectID: $openMenuProjectID
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollDisabled(workspaceDrag.isActive)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
        .padding(.vertical, StudioSpacing.toolbarVertical)
        .overlay(alignment: .trailing) {
            Text("New project")
                .font(StudioTypography.meta)
                .foregroundStyle(Color.accentColor)
                .padding(.trailing, StudioSpacing.panelHorizontal + 8)
                .opacity(isSplitHoverTarget ? 1 : 0)
                .allowsHitTesting(false)
        }
        .background {
            ZStack {
                Rectangle().fill(.bar)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .opacity(isSplitHoverTarget ? 1 : 0)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ProjectToolbarZoneFrameKey.self,
                    value: geometry.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(ProjectTabFrameKey.self) { frames in
            guard !workspaceDrag.isActive else { return }
            editor.workspaceDrag.setTabFrames(frames)
        }
        .onPreferenceChange(ProjectToolbarZoneFrameKey.self) { frame in
            guard !workspaceDrag.isActive else { return }
            editor.workspaceDrag.setToolbarFrame(frame)
        }
    }
}

private struct ProjectTabChip: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    let openProject: OpenProject
    @Binding var openMenuProjectID: String?

    private var isActive: Bool {
        editor.activeProjectID == openProject.id
    }

    private var isOpen: Bool {
        openMenuProjectID == openProject.id
    }

    private var isHoverTarget: Bool {
        if case let .project(id) = workspaceDrag.hoveredTarget {
            return id == openProject.id
        }
        return false
    }

    private var tabLabel: String {
        editor.projectTabLabel(for: openProject)
    }

    var body: some View {
        WorkspaceDraggableContainer(
            item: .project(projectID: openProject.id, label: tabLabel),
            isDragEnabled: editor.canDragProjectForCombine,
            helpText: "Drag to another project tab to combine projects",
            onBegin: { openMenuProjectID = nil },
            onTap: {
                if isActive && isOpen {
                    openMenuProjectID = nil
                } else {
                    editor.activateProject(id: openProject.id)
                    openMenuProjectID = openProject.id
                }
            }
        ) {
            StudioTabChip(
                isSelected: isActive || isOpen,
                isHighlighted: isHoverTarget,
                shape: .roundedRect
            ) {
                Text(tabLabel)
                    .font(StudioTypography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            } trailing: {
                Text("\(openProject.document.fonts.count)")
                    .font(StudioTypography.monoMeta)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                Image(systemName: "chevron.down")
                    .font(StudioTypography.iconGlyph)
                    .foregroundStyle(.secondary)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ProjectTabFrameKey.self,
                    value: [openProject.id: geometry.frame(in: .global)]
                )
            }
        }
        .anchorPreference(key: ProjectTabAnchorKey.self, value: .bounds) { anchor in
            [openProject.id: anchor]
        }
    }
}
