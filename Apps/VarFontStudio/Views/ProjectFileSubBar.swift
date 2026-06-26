import SwiftUI
import VarFontCore

/// Tier-2 file switcher below the project toolbar.
struct ProjectFileSubBar: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag

    var body: some View {
        Group {
            if editor.hasOpenProjects, let project = editor.project, !project.fonts.isEmpty {
                HStack(spacing: StudioSpacing.controlGap) {
                    Text("FILE")
                        .font(StudioTypography.sectionLabel)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(project.fonts) { font in
                                fileChip(font)
                            }
                        }
                    }
                    .scrollDisabled(workspaceDrag.isActive)
                }
                .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
                .padding(.vertical, 5)
                .background(.bar)
            }
        }
    }

    private func fileChip(_ font: FontDocument) -> some View {
        let isSelected = editor.selectedFontID == font.id
        let name = editor.fontBasename(for: font)
        let projectID = editor.activeProjectID ?? ""

        return WorkspaceDraggableContainer(
            item: .font(fontID: font.id, fromProjectID: projectID, label: name),
            isDragEnabled: editor.canDragFont(forProjectID: projectID),
            helpText: "Drag to a project tab to move, or to the toolbar to start a new project",
            onTap: {
                editor.selectFont(id: font.id)
            }
        ) {
            Text(name)
                .font(StudioTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? StudioColors.selectionFill : Color.primary.opacity(0.04),
                    in: Capsule()
                )
        }
    }
}
