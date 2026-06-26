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

struct FontMoveRequest: Identifiable, Equatable {
    var fontID: String
    var fromProjectID: String
    var toProjectID: String
    var id: String { "\(fromProjectID)-\(fontID)-\(toProjectID)" }
}

struct FontSplitRequest: Identifiable, Equatable {
    var fontID: String
    var fromProjectID: String
    var id: String { "split-\(fromProjectID)-\(fontID)" }
}

struct ProjectCombineRequest: Identifiable, Equatable {
    var sourceProjectID: String
    var targetProjectID: String
    var id: String { "\(sourceProjectID)-into-\(targetProjectID)" }
}

enum ProjectTargetPickerMode: Equatable, Identifiable {
    case moveFont(fontID: String, fromProjectID: String)
    case combineInto(targetProjectID: String)

    var id: String {
        switch self {
        case let .moveFont(fontID, fromProjectID):
            "move-\(fromProjectID)-\(fontID)"
        case let .combineInto(targetProjectID):
            "combine-into-\(targetProjectID)"
        }
    }
}
