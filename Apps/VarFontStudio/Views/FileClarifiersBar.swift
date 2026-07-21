import SwiftUI
import VarFontCore

/// File naming form label column (on-lattice).
enum FileNamingLayout {
    static let labelWidth: CGFloat = StudioSpace.unit * 18 // 72
}

/// File naming fields — PostScript prefix only (file identity lives on registration axes).
struct FileClarifierFields: View {
    @EnvironmentObject private var editor: EditorViewModel
    let font: FontDocument
    @FocusState private var postScriptPrefixFocused: Bool
    @State private var highlightPostScriptPrefix = false

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            postscriptPrefixRow(fontID: font.id)
            Text("Slope, width, and optical file identity use naming axes in the Axis Tree.")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: editor.inspectorFocus.revealToken) { _, _ in
            applyFileNamingFocusIfNeeded()
        }
        .onAppear {
            applyFileNamingFocusIfNeeded()
        }
    }

    private func applyFileNamingFocusIfNeeded() {
        guard editor.inspectorFocus.fileNamingFocus == .postScriptPrefix else { return }
        highlightPostScriptPrefix = true
        DispatchQueue.main.async {
            postScriptPrefixFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            highlightPostScriptPrefix = false
            editor.clearInspectorFileNamingFocus()
        }
    }

    private func postscriptPrefixRow(fontID: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StudioSpacing.controlGap) {
            Text("PostScript prefix")
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
                .frame(width: FileNamingLayout.labelWidth, alignment: .leading)

            StudioTextField(
                placeholder: "FamilyVariable",
                text: psPrefixBinding(for: fontID),
                filledForeground: StudioColors.registrationForeground,
                focusBinding: $postScriptPrefixFocused
            )
            .help(psPrefixHelp(for: fontID))
            .overlay {
                if highlightPostScriptPrefix {
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.5)
                }
            }
        }
    }

    private func psPrefixHelp(for fontID: String) -> String {
        let isMaster = editor.isMasterFont(fontID: fontID, projectID: editor.activeProjectID ?? "")
        if isMaster {
            return "Prefix for fvar instance PostScript names. Editing the master updates every file in this project."
        }
        return "Prefix for fvar instance PostScript names on this file only. Edit the master file to push a shared prefix to the whole project."
    }

    private func psPrefixBinding(for fontID: String) -> Binding<String> {
        Binding(
            get: { editor.familyPSPrefix(for: fontID) },
            set: { editor.setFamilyPSPrefix($0, for: fontID) }
        )
    }
}

/// Placeholder when no file is selected in the project inspector.
struct FileNamingSectionPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.groupHeaderBelow) {
            StudioSectionLabel(title: "File naming", muted: false)
            Text("Select a file")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
        }
    }
}
