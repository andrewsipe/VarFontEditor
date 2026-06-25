import SwiftUI

/// Shown after drop on teal zone when multiple projects are open.
struct ProjectPickerSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Add to project")
                .font(StudioTypography.emphasis)

            Text("Choose which project should receive the dropped font file.")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(StudioTypography.sectionLabel)
                    .foregroundStyle(.secondary)

                Picker("Project", selection: $selectedProjectID) {
                    ForEach(editor.openProjects) { op in
                        Text(projectPickerLabel(for: op)).tag(op.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StudioRadius.chip))

            HStack {
                Spacer()
                Button("Cancel") {
                    editor.cancelPendingDrop()
                    dismiss()
                }
                Button("Add") {
                    Task {
                        await editor.completePendingDrop(addToProjectID: selectedProjectID)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            selectedProjectID = editor.activeProjectID ?? editor.openProjects.first?.id ?? ""
        }
    }

    private func projectPickerLabel(for openProject: OpenProject) -> String {
        let name = editor.projectTabLabel(for: openProject)
        let count = openProject.document.fonts.count
        return "\(name) (\(count) file\(count == 1 ? "" : "s"))"
    }
}
