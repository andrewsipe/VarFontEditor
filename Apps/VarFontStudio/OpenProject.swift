import Foundation
import VarFontCore

/// One project tab in the workspace session.
struct OpenProject: Identifiable, Equatable {
    var id: String
    var document: ProjectDocument
    var selectedFontID: String?
    var undoStack: [ProjectDocument] = []
    var redoStack: [ProjectDocument] = []

    init(document: ProjectDocument, selectedFontID: String? = nil) {
        id = UUID().uuidString
        self.document = document
        self.selectedFontID = selectedFontID ?? document.fonts.first?.id
    }
}

enum FontDropDisposition: Equatable {
    case createNewProject
    case addToProject
}

struct FontRemovalRequest: Identifiable, Equatable {
    var projectID: String
    var fontID: String
    var id: String { "\(projectID)-\(fontID)" }
}
