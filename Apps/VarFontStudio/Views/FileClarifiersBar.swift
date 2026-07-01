import SwiftUI
import VarFontCore

/// File naming fields — right column of the project dropdown menu.
struct FileNamingSection: View {
    @EnvironmentObject private var editor: EditorViewModel
    let font: FontDocument

    private var clarifiersEditable: Bool {
        editor.areFileClarifiersEditable(for: font.id)
    }

    private var isMaster: Bool {
        editor.fileRole(for: font.id)?.kind == .master
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.groupHeaderBelow) {
            sectionHeader

            VStack(alignment: .leading, spacing: 5) {
                postscriptPrefixRow(fontID: font.id)
                ForEach(FileClarifierCategory.allCases, id: \.self) { category in
                    clarifierRow(category: category, fontID: font.id)
                }
            }
        }
        .frame(width: StudioPanelMetrics.projectMenuNamingWidth, alignment: .leading)
    }

    private var sectionHeader: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            StudioSectionLabel(title: "File naming", muted: false)
            Spacer(minLength: 0)

            Button("Infer") {
                editor.selectFont(id: font.id)
                editor.inferFileClarifiersForSelectedFont()
            }
            .font(StudioTypography.meta)
            .buttonStyle(.plain)
            .help("Guess clarifiers from filename and existing names")

            if hasOverflowActions {
                StudioToolbarIconMenu {
                    overflowMenuContent
                }
            }
        }
        .frame(height: StudioFieldMetrics.disclosureLabelRowHeight)
    }

    private var hasOverflowActions: Bool {
        if isMaster, editor.projectHasMultipleFiles { return true }
        if !isMaster { return true }
        return false
    }

    @ViewBuilder
    private var overflowMenuContent: some View {
        if isMaster, editor.projectHasMultipleFiles {
            Button {
                editor.selectFont(id: font.id)
                editor.pushMasterAxisTreeToAllFonts()
            } label: {
                Label("Push tree from master…", systemImage: "arrow.triangle.branch")
            }

            if !editor.clarifierLabels(for: font.id).isEmpty {
                Button {
                    editor.selectFont(id: font.id)
                    editor.clearFileClarifiers(for: font.id)
                } label: {
                    Label("Clear clarifiers", systemImage: "xmark.circle")
                }
            }
        }

        if !isMaster {
            Button {
                editor.selectFont(id: font.id)
                editor.setFontAsMaster(fontID: font.id)
            } label: {
                Label("Set as master", systemImage: "star")
            }
        }
    }

    private func postscriptPrefixRow(fontID: String) -> some View {
        HStack(spacing: 8) {
            Text("PostScript prefix")
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            StudioTextField(
                placeholder: "MilgramVariable",
                text: psPrefixBinding(for: fontID),
                filledForeground: StudioColors.clarifierForeground
            )
            .help("Prefix for fvar instance PostScript names — from name ID 25, or ID 6 before the first hyphen")
        }
    }

    private func clarifierRow(category: FileClarifierCategory, fontID: String) -> some View {
        HStack(spacing: 8) {
            Text(category.rawValue)
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            StudioTextField(
                placeholder: categoryPlaceholder(category),
                text: binding(for: category, fontID: fontID),
                filledForeground: StudioColors.clarifierForeground
            )
            .disabled(!clarifiersEditable)
            .help(clarifiersEditable ? clarifierFieldHelp : "Set on variant files in this project")
        }
    }

    private var clarifierFieldHelp: String {
        "File-level naming token appended before axis stop names. Clear a field to omit that clarifier."
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
        case .custom: return "Rounded Stencil Rough"
        }
    }
}
