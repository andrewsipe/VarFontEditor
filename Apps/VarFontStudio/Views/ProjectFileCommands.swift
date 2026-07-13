import SwiftUI
import VarFontCore

/// Shared file actions for the sub-bar chips and project inspector rows.
struct ProjectFileContextMenu: View {
    @EnvironmentObject private var editor: EditorViewModel
    let font: FontDocument
    let projectID: String
    let projectFontCount: Int

    private var isMaster: Bool {
        editor.isMasterFont(fontID: font.id, projectID: projectID)
    }

    var body: some View {
        Group {
            if projectFontCount > 1, !isMaster {
                Button {
                    editor.activateProject(id: projectID)
                    editor.selectFont(id: font.id)
                    editor.requestSetAsMaster(fontID: font.id)
                } label: {
                    Label("Set as master", systemImage: "star")
                }
            }

            Button {
                editor.activateProject(id: projectID)
                editor.selectFont(id: font.id)
                editor.revealFontInFinder(fontID: font.id, projectID: projectID)
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
            }

            if editor.openProjects.count > 1 {
                Button {
                    editor.presentMoveFontPicker(fontID: font.id, fromProjectID: projectID)
                } label: {
                    Label("Move to…", systemImage: "arrow.right.circle")
                }
            }

            if projectFontCount > 1 {
                Button {
                    editor.requestSplitFontToNewProject(fontID: font.id, fromProjectID: projectID)
                } label: {
                    Label("Move to new project…", systemImage: "arrow.up.right.square")
                }

                Divider()

                Button(role: .destructive) {
                    editor.requestRemoveFont(projectID: projectID, fontID: font.id)
                } label: {
                    Label("Remove from project", systemImage: "minus.circle")
                }
            }
        }
    }
}
