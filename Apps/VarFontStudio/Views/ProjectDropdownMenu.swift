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

            Text("OPEN FONTS · \(openProject.document.fonts.count)")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ForEach(openProject.document.fonts) { font in
                fileRow(font)
            }

            Divider()
                .padding(.top, 4)

            HStack(spacing: 6) {
                Button("Reveal in Finder") {
                    if isActiveProject, editor.selectedFontID == nil {
                        editor.selectFont(id: openProject.document.fonts.first?.id ?? "")
                    }
                    if isActiveProject {
                        editor.revealActiveFontInFinder()
                    } else {
                        editor.activateProject(id: openProject.id)
                        if let first = openProject.document.fonts.first?.id {
                            editor.selectFont(id: first)
                        }
                        editor.revealActiveFontInFinder()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Add font…") {
                    onDismiss()
                    editor.presentAddFontPanel(projectID: openProject.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)

            Button("Remove project") {
                onDismiss()
                editor.requestCloseProject(id: openProject.id)
            }
            .font(StudioTypography.meta)
            .foregroundStyle(.red)
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
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

    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isEditingName {
                    TextField("Project name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .font(StudioTypography.bodyMedium)
                        .focused($nameFieldFocused)
                        .onSubmit { commitRename() }

                    Button("Done") { commitRename() }
                        .controlSize(.small)
                } else {
                    Text(currentDisplayName)
                        .font(StudioTypography.bodyMedium)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Button {
                        editedName = currentDisplayName
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Rename project tab")
                }

                Spacer(minLength: 0)
            }

            Text("\(openProject.document.fonts.count) file\(openProject.document.fonts.count == 1 ? "" : "s") · \(openProject.document.familyLabel)")
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.renameProject(id: openProject.id, displayName: trimmed)
        isEditingName = false
        nameFieldFocused = false
        editedName = currentDisplayName
    }

    private func fileRow(_ font: FontDocument) -> some View {
        let isSelected = isActiveProject && editor.selectedFontID == font.id
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.fontBasename(for: font))
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
            .contentShape(Rectangle())
            .onTapGesture {
                editor.activateProject(id: openProject.id)
                editor.selectFont(id: font.id)
            }

            Button("Remove") {
                editor.requestRemoveFont(projectID: openProject.id, fontID: font.id)
            }
            .font(StudioTypography.meta)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Remove file from project")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? StudioColors.selectionFill : Color.clear,
            in: RoundedRectangle(cornerRadius: StudioRadius.chip)
        )
    }
}
