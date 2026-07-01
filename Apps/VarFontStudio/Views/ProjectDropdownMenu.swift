import SwiftUI
import VarFontCore

/// Source-manager dropdown for one project tab.
struct ProjectDropdownMenu: View {
    @EnvironmentObject private var editor: EditorViewModel
    let openProject: OpenProject
    var onDismiss: () -> Void

    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var nameFieldFocused: Bool

    private var liveProject: OpenProject? {
        editor.openProjects.first(where: { $0.id == openProject.id })
    }

    private var isActiveProject: Bool {
        editor.activeProjectID == openProject.id
    }

    private var clarifierFont: FontDocument? {
        guard isActiveProject,
              let fontID = editor.selectedFontID,
              let font = openProject.document.fonts.first(where: { $0.id == fontID })
        else { return nil }
        return font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader

            menuHairline

            HStack(alignment: .top, spacing: StudioSpacing.sheetSectionSpacing) {
                filesSection

                if let font = clarifierFont {
                    FileNamingSection(font: font)
                }
            }
            .padding(.top, StudioSpacing.sheetSectionSpacing)
        }
        .padding(StudioSpacing.sheetOuterPadding)
        .id(openProject.id)
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

    private var currentDisplayName: String {
        if let name = liveProject?.document.displayName, !name.isEmpty {
            return name
        }
        return editor.projectTabLabel(for: liveProject ?? openProject)
    }

    private var menuHairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.22))
            .frame(height: 1)
            .padding(.top, StudioSpacing.controlGap)
    }

    private var projectHeader: some View {
        HStack(alignment: .top, spacing: StudioSpacing.controlGap) {
            Group {
                if isEditingName {
                    projectHeaderContent
                } else {
                    WorkspaceDraggableContainer(
                        item: .project(projectID: openProject.id, label: currentDisplayName),
                        isDragEnabled: editor.canDragProjectForCombine,
                        helpText: "Drag to another project tab to combine projects"
                    ) {
                        projectHeaderContent
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
                projectHeaderActions
            }
        }
    }

    private var projectHeaderContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if isEditingName {
                    StudioTextField(
                        placeholder: "Project name",
                        text: $editedName,
                        font: StudioTypography.emphasis,
                        rowHeight: StudioFieldMetrics.bodyMediumRowHeight
                    )
                    .focused($nameFieldFocused)
                    .onSubmit { commitRename() }
                } else {
                    Text(currentDisplayName)
                        .font(StudioTypography.emphasis)
                        .lineLimit(2)
                }
            }
            .transaction { $0.animation = nil }

            Text("\(openProject.document.fonts.count) file\(openProject.document.fonts.count == 1 ? "" : "s") · \(openProject.document.familyLabel)")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var projectHeaderActions: some View {
        HStack(spacing: 0) {
            StudioToolbarIconButton(systemName: "pencil.circle", help: "Rename project tab") {
                editedName = currentDisplayName
                isEditingName = true
            }

            StudioToolbarIconMenu {
                projectActionsMenuContent
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.groupHeaderBelow) {
            StudioSectionLabel(title: "Open fonts · \(openProject.document.fonts.count)", muted: false)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(openProject.document.fonts) { font in
                    ProjectMenuFileRow(
                        font: font,
                        openProject: openProject,
                        isSelected: isActiveProject && editor.selectedFontID == font.id,
                        onDismiss: onDismiss
                    )
                }
            }
        }
        .frame(width: StudioPanelMetrics.projectMenuListWidth, alignment: .leading)
    }

    @ViewBuilder
    private var projectActionsMenuContent: some View {
        Button {
            onDismiss()
            editor.presentAddFontPanel(projectID: openProject.id)
        } label: {
            Label("Add font…", systemImage: "folder.badge.plus")
        }

        Button {
            onDismiss()
            editor.presentSaveReviewWindow(forProjectID: openProject.id)
        } label: {
            Label("Open Save Review Window", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(!editor.canPreviewSaveReview(forProjectID: openProject.id))

        if openProject.document.fonts.count > 1 {
            Button {
                onDismiss()
                editor.saveAllFiles(inProjectID: openProject.id)
            } label: {
                Label("Save All Files…", systemImage: "square.and.arrow.down.on.square")
            }
            .disabled(!editor.canSave || editor.isSaveActionBlocked)
        }

        if let masterID = editor.masterFontID(for: openProject.id),
           openProject.document.fonts.count > 1 {
            Button {
                onDismiss()
                editor.selectFont(id: masterID)
                editor.pushMasterAxisTreeToAllFonts()
            } label: {
                Label("Push tree from master…", systemImage: "arrow.triangle.branch")
            }
        }

        if editor.openProjects.count > 1 {
            Button {
                onDismiss()
                editor.presentCombineProjectsPicker(into: openProject.id)
            } label: {
                Label("Combine with…", systemImage: "arrow.triangle.merge")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDismiss()
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
}

// MARK: - File row

private struct ProjectMenuFileRow: View {
    @EnvironmentObject private var editor: EditorViewModel
    let font: FontDocument
    let openProject: OpenProject
    let isSelected: Bool
    let onDismiss: () -> Void

    @State private var isHovered = false

    private var name: String {
        editor.fontBasename(for: font)
    }

    var body: some View {
        HStack(alignment: .center, spacing: StudioSpacing.controlGap) {
            WorkspaceDraggableContainer(
                item: .font(fontID: font.id, fromProjectID: openProject.id, label: name),
                isDragEnabled: editor.canDragFont(forProjectID: openProject.id),
                helpText: "Drag to a project tab to move, or to the toolbar to start a new project",
                onTap: {
                    editor.activateProject(id: openProject.id)
                    editor.selectFont(id: font.id)
                }
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(StudioTypography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(editor.shortenedPath(font.sourcePath))
                        .font(StudioTypography.monoMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(font.axes.count) axes · \(editor.instanceCountLabel(for: font)) instances · \(openProject.document.familyLabel)")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            fileActionsMenu
        }
        .padding(.horizontal, StudioSpacing.rowHorizontal)
        .padding(.vertical, 5)
        .background {
            StudioRowBackground(isSelected: isSelected, isHovered: isHovered)
        }
        .contentShape(RoundedRectangle(cornerRadius: StudioRadius.row))
        .onHover { isHovered = $0 }
    }

    private var fileActionsMenu: some View {
        StudioToolbarIconMenu {
            Button {
                editor.activateProject(id: openProject.id)
                editor.selectFont(id: font.id)
                editor.revealFontInFinder(fontID: font.id, projectID: openProject.id)
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }

            if editor.openProjects.count > 1 {
                Button {
                    onDismiss()
                    editor.presentMoveFontPicker(fontID: font.id, fromProjectID: openProject.id)
                } label: {
                    Label("Move to…", systemImage: "arrow.right.circle")
                }
            }

            if openProject.document.fonts.count > 1 {
                Button {
                    onDismiss()
                    editor.requestSplitFontToNewProject(fontID: font.id, fromProjectID: openProject.id)
                } label: {
                    Label("Move to new project…", systemImage: "arrow.up.right.square")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDismiss()
                editor.requestRemoveFont(projectID: openProject.id, fontID: font.id)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }
}
