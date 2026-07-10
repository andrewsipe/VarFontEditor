import SwiftUI
import VarFontCore

/// Scrollable file row used in the project inspector file list.
struct ProjectInspectorFileRow: View {
    @EnvironmentObject private var editor: EditorViewModel
    let font: FontDocument
    let openProject: OpenProject
    let isSelected: Bool

    @State private var isHovered = false

    private var name: String {
        editor.fontBasename(for: font)
    }

    private var isMaster: Bool {
        editor.isMasterFont(fontID: font.id, projectID: openProject.id)
            && openProject.document.fonts.count > 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: StudioSpacing.controlGap) {
            WorkspaceDraggableContainer(
                item: .font(fontID: font.id, fromProjectID: openProject.id, label: name),
                isDragEnabled: editor.canDragFont(forProjectID: openProject.id),
                helpText: "Drag onto another file to reorder, to a project tab to move, or to the toolbar to start a new project",
                onTap: {
                    editor.selectFont(id: font.id)
                    editor.focusInspectorProjectScope()
                }
            ) {
                HStack(spacing: 5) {
                    if isMaster {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(StudioColors.computedHighlight)
                            .help("Master — axis tree source for this project")
                    }
                    if editor.isFontDirty(fontID: font.id) {
                        StudioDirtyDot()
                            .help("Unsaved edits")
                    }
                    Text(name)
                        .font(StudioTypography.bodyMedium)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(editor.instanceCountLabel(for: font))
                        .font(StudioTypography.monoMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            StudioToolbarIconMenu {
                ProjectFileContextMenu(
                    font: font,
                    projectID: openProject.id,
                    projectFontCount: openProject.document.fonts.count
                )
            }
        }
        .padding(.horizontal, StudioSpacing.rowHorizontal)
        .padding(.vertical, 6)
        .background {
            StudioRowBackground(isSelected: isSelected, isHovered: isHovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: StudioRadius.row))
        .onHover { isHovered = $0 }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FileChipFrameKey.self,
                    value: ["\(openProject.id):\(font.id)": geometry.frame(in: .global)]
                )
            }
        }
        .contextMenu {
            ProjectFileContextMenu(
                font: font,
                projectID: openProject.id,
                projectFontCount: openProject.document.fonts.count
            )
        }
    }
}
