import SwiftUI
import VarFontCore

struct ProjectToolbar: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag

    private var isNewProjectTarget: Bool {
        workspaceDrag.isHighlightingNewProject
    }

    private var showsNewProjectHint: Bool {
        workspaceDrag.isExternalFileDropActive
    }

    private var highlightsToolbarRow: Bool {
        workspaceDrag.shouldHighlightProjectToolbarRow
    }

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(editor.openProjects) { openProject in
                        ProjectTabChip(openProject: openProject)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollDisabled(workspaceDrag.isActive)

            Spacer(minLength: 0)

            if showsNewProjectHint {
                newProjectAffordance
            }
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
        .padding(.vertical, StudioSpacing.toolbarVertical)
        .workspaceDropZoneHighlight(
            isActive: highlightsToolbarRow,
            tint: StudioColors.dropNewProject
        )
        .background(.bar)
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

    private var newProjectAffordance: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 10, weight: .semibold))
            Text("New project")
                .font(StudioTypography.meta)
                .fontWeight(isNewProjectTarget ? .semibold : .regular)
        }
        .foregroundStyle(StudioColors.dropNewProject.opacity(isNewProjectTarget ? 0.95 : 0.45))
        .padding(.trailing, 4)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: isNewProjectTarget)
    }
}

private struct ProjectTabChip: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    let openProject: OpenProject

    private var isActive: Bool {
        editor.activeProjectID == openProject.id
    }

    private var isInternalHoverTarget: Bool {
        if case .project(let id) = workspaceDrag.hoveredTarget {
            return id == openProject.id
        }
        return false
    }

    private var isExternalTabTarget: Bool {
        workspaceDrag.shouldHighlightProjectTab(
            openProject.id,
            activeProjectID: editor.activeProjectID
        )
    }

    private var tabLabel: String {
        editor.projectTabLabel(for: openProject)
    }

    var body: some View {
        StudioTabChip(
            isSelected: isActive,
            isHighlighted: isInternalHoverTarget && workspaceDrag.isActive,
            isDropTarget: isExternalTabTarget,
            dropTargetTint: StudioColors.dropAddExisting,
            shape: .roundedRect
        ) {
            WorkspaceDraggableContainer(
                item: .project(projectID: openProject.id, label: tabLabel),
                isDragEnabled: editor.canDragProjectForCombine,
                helpText: "Drag to another project tab to combine projects"
            ) {
                Text(tabLabel)
                    .font(StudioTypography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isActive {
                            editor.activateProject(id: openProject.id)
                        }
                    }
            }
        } trailing: {
            HStack(spacing: 4) {
                Text("\(openProject.document.fonts.count)")
                    .font(StudioTypography.monoMeta)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                StudioToolbarIconMenu(help: "Project actions") {
                    ProjectTabContextMenu(projectID: openProject.id)
                }
            }
        }
        .contextMenu {
            ProjectTabContextMenu(projectID: openProject.id)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ProjectTabFrameKey.self,
                    value: [openProject.id: geometry.frame(in: .global)]
                )
            }
        }
    }
}

private struct ProjectTabContextMenu: View {
    @EnvironmentObject private var editor: EditorViewModel
    let projectID: String

    var body: some View {
        Button(role: .destructive) {
            editor.requestCloseProject(id: projectID)
        } label: {
            Label("Remove project", systemImage: "xmark.circle")
        }
    }
}
