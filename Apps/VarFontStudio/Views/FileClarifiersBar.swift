import SwiftUI
import VarFontCore

/// File naming field rows only — used inside the project inspector naming block.
struct FileClarifierFields: View {
    @EnvironmentObject private var editor: EditorViewModel
    let font: FontDocument
    @FocusState private var postScriptPrefixFocused: Bool
    @State private var highlightPostScriptPrefix = false

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            postscriptPrefixRow(fontID: font.id)
            ForEach(FileClarifierCategory.allCases, id: \.self) { category in
                clarifierRow(category: category, fontID: font.id)
            }
        }
        .onChange(of: editor.inspectorRevealToken) { _, _ in
            applyFileNamingFocusIfNeeded()
        }
        .onAppear {
            applyFileNamingFocusIfNeeded()
        }
    }

    private func applyFileNamingFocusIfNeeded() {
        guard editor.inspectorFileNamingFocus == .postScriptPrefix else { return }
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("PostScript prefix")
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            StudioTextField(
                placeholder: "FamilyVariable",
                text: psPrefixBinding(for: fontID),
                filledForeground: StudioColors.clarifierForeground,
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

    @ViewBuilder
    private func clarifierRow(category: FileClarifierCategory, fontID: String) -> some View {
        let state = editor.clarifierSlotState(category: category, for: fontID)
        HStack(alignment: .center, spacing: 8) {
            ClarifierTokenPill(category: category)
                .opacity(state.isEditable ? 1 : 0.6)
                .frame(width: 72, alignment: .leading)

            Group {
                switch state {
                case .coveredByRegistration:
                    Text("Covered by STAT registration")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Naming for this slot comes from the registration axis on this file.")

                case .coveredByInstanceAxis(let axisTag):
                    HStack(spacing: 6) {
                        Text("Covered by axis stops")
                            .font(StudioTypography.meta)
                            .foregroundStyle(.tertiary)
                        StudioTagPill(text: axisTag, compact: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Instance axis stop names on this file already name this dimension.")

                case .readOnlyMaster:
                    Text("Set on variant files in this project")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Set on variant files in this project")

                case .editable:
                    StudioTextField(
                        placeholder: categoryPlaceholder(category),
                        text: binding(for: category, fontID: fontID),
                        filledForeground: StudioColors.clarifierForeground
                    )
                    .help(clarifierFieldHelp)
                }
            }
            .frame(minHeight: StudioFieldMetrics.captionRowHeight)
        }
    }

    private var clarifierFieldHelp: String {
        "File-level naming label appended before axis stop names. Clear a field to omit that clarifier."
    }

    private func psPrefixBinding(for fontID: String) -> Binding<String> {
        Binding(
            get: { editor.familyPSPrefix(for: fontID) },
            set: { editor.setFamilyPSPrefix($0, for: fontID) }
        )
    }

    private func binding(for category: FileClarifierCategory, fontID: String) -> Binding<String> {
        Binding(
            get: {
                editor.clarifierLabels(for: fontID).first { $0.category == category }?.label ?? ""
            },
            set: { newValue in
                editor.setFileClarifier(category: category, label: newValue, for: fontID)
            }
        )
    }

    private func categoryPlaceholder(_ category: FileClarifierCategory) -> String {
        switch category {
        case .slope: return "Italic"
        case .width: return "Condensed"
        case .optical: return "Display"
        case .custom: return "Optional token"
        }
    }
}

/// Category-key pill for clarifier rows — same shape as `StudioTagPill`, but in the
/// clarifier-purple that `StudioColors` reserves for per-file naming metadata
/// (distinct from `.instance` gray and `.registration` teal).
struct ClarifierTokenPill: View {
    let category: FileClarifierCategory

    private var displayLabel: String {
        NamingToken.clarifierPillLabel(for: category)
    }

    private var tooltip: String {
        "Inserts the \(NamingToken.token(for: category)) token"
    }

    var body: some View {
        Text(displayLabel)
            .font(StudioTypography.tag)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(StudioColors.clarifierForeground)
            .background(StudioColors.clarifierBackground, in: RoundedRectangle(cornerRadius: StudioRadius.small))
            .help(tooltip)
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

private extension ClarifierSlotState {
    var isEditable: Bool {
        if case .editable = self { return true }
        return false
    }
}
