import SwiftUI

/// Pick another open project when moving a font or combining projects.
struct ProjectTargetPickerSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectID: String = ""

    let mode: ProjectTargetPickerMode

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text(title)
                .font(StudioTypography.emphasis)

            Text(subtitle)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)

            if candidateProjects.isEmpty {
                Text(emptyMessage)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project")
                        .font(StudioTypography.sectionLabel)
                        .foregroundStyle(.secondary)

                    Picker("Project", selection: $selectedProjectID) {
                        ForEach(candidateProjects) { openProject in
                            Text(projectPickerLabel(for: openProject)).tag(openProject.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    editor.cancelProjectTargetPicker()
                    dismiss()
                }
                Button(primaryActionTitle) {
                    editor.completeProjectTargetPicker(selectedProjectID: selectedProjectID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProjectID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            selectedProjectID = candidateProjects.first?.id ?? ""
        }
    }

    private var candidateProjects: [OpenProject] {
        switch mode {
        case let .moveFont(_, fromProjectID):
            editor.openProjects.filter { $0.id != fromProjectID }
        case let .combineInto(targetProjectID):
            editor.openProjects.filter { $0.id != targetProjectID }
        }
    }

    private var title: String {
        switch mode {
        case .moveFont:
            "Move to project"
        case .combineInto:
            "Combine with project"
        }
    }

    private var subtitle: String {
        switch mode {
        case .moveFont:
            "Move this font file into another open project."
        case .combineInto:
            "Move all files from the selected project into this one, then close it."
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .moveFont:
            "Open another project tab to move this file."
        case .combineInto:
            "Open another project tab to combine with this one."
        }
    }

    private var primaryActionTitle: String {
        switch mode {
        case .moveFont:
            "Move"
        case .combineInto:
            "Combine"
        }
    }

    private func projectPickerLabel(for openProject: OpenProject) -> String {
        let name = editor.projectTabLabel(for: openProject)
        let count = openProject.document.fonts.count
        return "\(name) (\(count) file\(count == 1 ? "" : "s"))"
    }
}
