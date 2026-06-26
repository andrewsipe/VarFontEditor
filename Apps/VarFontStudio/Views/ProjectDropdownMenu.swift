import SwiftUI
import VarFontCore

/// Source-manager dropdown for one project tab (Option B layout).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader

            menuSectionDivider

            Text("OPEN FONTS · \(openProject.document.fonts.count)")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ForEach(openProject.document.fonts) { font in
                fileRow(font)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 360)
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

    private var menuSectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.22))
            .frame(height: 1)
    }

    private var projectHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            if !isEditingName {
                WorkspaceDraggableContainer(
                    item: .project(projectID: openProject.id, label: currentDisplayName),
                    isDragEnabled: editor.canDragProjectForCombine,
                    helpText: "Drag to another project tab to combine projects"
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentDisplayName)
                            .font(StudioTypography.bodyMedium)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text("\(openProject.document.fonts.count) file\(openProject.document.fonts.count == 1 ? "" : "s") · \(openProject.document.familyLabel)")
                            .font(StudioTypography.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                projectHeaderActions
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Project name", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                            .font(StudioTypography.bodyMedium)
                            .focused($nameFieldFocused)
                            .onSubmit { commitRename() }

                        Button("Done") { commitRename() }
                            .controlSize(.small)
                    }

                    Text("\(openProject.document.fonts.count) file\(openProject.document.fonts.count == 1 ? "" : "s") · \(openProject.document.familyLabel)")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal)
        .padding(.vertical, 8)
        .padding(.top, 6)
    }

    private var projectHeaderActions: some View {
        HStack(spacing: 2) {
            ProjectRowIconButton(systemName: "pencil.circle", help: "Rename project tab") {
                editedName = currentDisplayName
                isEditingName = true
            }

            projectActionsMenu
        }
        .padding(.top, 1)
    }

    private var projectActionsMenu: some View {
        ProjectRowMenu {
            Button {
                onDismiss()
                editor.presentAddFontPanel(projectID: openProject.id)
            } label: {
                Label("Add font…", systemImage: "folder.badge.plus")
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
    }

    private func fileRow(_ font: FontDocument) -> some View {
        let isSelected = isActiveProject && editor.selectedFontID == font.id
        let name = editor.fontBasename(for: font)

        return HStack(alignment: .top, spacing: 8) {
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

            fileActionsMenu(font)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? StudioColors.selectionFill : Color.clear,
            in: RoundedRectangle(cornerRadius: StudioRadius.chip)
        )
    }

    private func fileActionsMenu(_ font: FontDocument) -> some View {
        ProjectRowMenu {
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

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.renameProject(id: openProject.id, displayName: trimmed)
        isEditingName = false
        nameFieldFocused = false
        editedName = currentDisplayName
    }
}

private struct ProjectRowIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ProjectRowMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Actions")
    }
}
