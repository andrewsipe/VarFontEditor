import SwiftUI
import VarFontCore

/// Project title band in the project inspector — distinct from file rows.
struct ProjectScopeHeader: View {
    @EnvironmentObject private var editor: EditorViewModel
    let openProject: OpenProject

    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var nameFieldFocused: Bool

    /// Matches the instance name in `StudioComposedNameCallout` — the project's own
    /// name deserves the same visual weight as the thing you're currently inspecting.
    private static let titleFont = Font.system(size: 15, weight: .semibold)

    private var liveProject: OpenProject? {
        editor.openProjects.first(where: { $0.id == openProject.id })
    }

    private var currentDisplayName: String {
        if let name = liveProject?.document.displayName, !name.isEmpty {
            return name
        }
        return editor.projectTabLabel(for: liveProject ?? openProject)
    }

    var body: some View {
        HStack(alignment: .top, spacing: StudioSpacing.controlGap) {
            Group {
                if isEditingName {
                    titleContent
                } else {
                    WorkspaceDraggableContainer(
                        item: .project(projectID: openProject.id, label: currentDisplayName),
                        isDragEnabled: editor.canDragProjectForCombine,
                        helpText: "Drag to another project tab to combine projects"
                    ) {
                        titleContent
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transaction { $0.animation = nil }

            if isEditingName {
                Button("Done") { commitRename() }
                    .controlSize(.small)
                    .frame(height: StudioFieldMetrics.bodyMediumRowHeight)
            } else {
                headerActions
            }
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal)
        .padding(.vertical, 12)
        .background(StudioColors.surfaceMuted)
        .onAppear {
            editedName = currentDisplayName
        }
        .onChange(of: isEditingName) { _, editing in
            if editing {
                DispatchQueue.main.async {
                    nameFieldFocused = true
                }
            }
        }
        .onChange(of: editor.openProjects) { _, _ in
            if !isEditingName {
                editedName = currentDisplayName
            }
        }
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isEditingName {
                    StudioTextField(
                        placeholder: "Project name",
                        text: $editedName,
                        font: Self.titleFont,
                        rowHeight: StudioFieldMetrics.bodyMediumRowHeight,
                        onSubmit: commitRename,
                        onCancel: cancelRename
                    )
                    .focused($nameFieldFocused)
                } else {
                    Text(currentDisplayName)
                        .font(Self.titleFont)
                        .lineLimit(2)
                }
            }
            .transaction { $0.animation = nil }

            HStack(spacing: 0) {
                let fileCount = liveProject?.document.fonts.count ?? openProject.document.fonts.count
                Text("\(fileCount)")
                    .foregroundStyle(StudioColors.computedHighlight)
                Text(" file\(fileCount == 1 ? "" : "s") · \(editor.projectNamingSubtitle(for: liveProject ?? openProject))")
                    .foregroundStyle(.secondary)
            }
            .font(StudioTypography.caption)
            .lineLimit(2)
            .help("PostScript prefix shared for instance names in this project")
        }
    }

    private var headerActions: some View {
        HStack(spacing: 0) {
            StudioToolbarIconButton(systemName: "pencil.circle", help: "Rename project tab") {
                editedName = currentDisplayName
                isEditingName = true
            }

            StudioToolbarIconMenu {
                projectScopeMenuContent
            }
        }
    }

    @ViewBuilder
    private var projectScopeMenuContent: some View {
        if editor.openProjects.count > 1 {
            Button {
                editor.presentCombineProjectsPicker(into: openProject.id)
            } label: {
                Label("Combine with…", systemImage: "arrow.triangle.merge")
            }
        }

        Button {
            editor.presentSaveReviewWindow(forProjectID: openProject.id)
        } label: {
            Label("Open Save Review Window", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(!editor.canPreviewSaveReview(forProjectID: openProject.id))

        Divider()

        Button(role: .destructive) {
            editor.requestCloseProject(id: openProject.id)
        } label: {
            Label("Remove project", systemImage: "xmark.circle")
        }
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.renameProject(id: openProject.id, displayName: trimmed)
        isEditingName = false
        nameFieldFocused = false
        editedName = currentDisplayName
    }

    private func cancelRename() {
        isEditingName = false
        nameFieldFocused = false
        editedName = currentDisplayName
    }
}
