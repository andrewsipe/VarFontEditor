import SwiftUI
import VarFontCore

/// Project-scoped inspector: fixed header + file naming, scrollable file list.
/// Sections are flat (no card backgrounds) to match StudioInspectorBlock's
/// convention in the Instance scope — a Divider marks the fixed/scroll seam.
struct ProjectInspectorPanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    @State private var isFileNamingExpanded = true

    var body: some View {
        if let projectID = editor.activeProjectID,
           let openProject = editor.openProjects.first(where: { $0.id == projectID }) {
            VStack(alignment: .leading, spacing: 0) {
                ProjectScopeHeader(openProject: openProject)

                fileNamingSection(for: openProject)
                    .padding(.horizontal, StudioSpacing.panelHorizontal)
                    .padding(.top, StudioSpacing.panelContentTop)
                    .padding(.bottom, StudioSpacing.sheetSectionSpacing)

                Divider()

                filesSection(for: openProject)
                    .padding(.horizontal, StudioSpacing.panelHorizontal)
                    .padding(.top, StudioSpacing.sheetSectionSpacing)
                    .padding(.bottom, StudioSpacing.panelVertical)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func fileNamingSection(for openProject: OpenProject) -> some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            if let fontID = editor.selectedFontID,
               let font = openProject.document.fonts.first(where: { $0.id == fontID }) {
                fileNamingHeader(font: font)

                if isFileNamingExpanded {
                    FileNamingFields(font: font)
                }
            } else {
                FileNamingSectionPlaceholder()
            }
        }
    }

    private func fileNamingHeader(font: FontDocument) -> some View {
        HStack(alignment: .center, spacing: StudioSpacing.controlGap) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    isFileNamingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    StudioDisclosureChevron(isExpanded: isFileNamingExpanded)
                    StudioSectionLabel(title: "File naming")
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if isFileNamingExpanded {
                fileNamingActions(font: font)
            }
        }
    }

    @ViewBuilder
    private func filesSection(for openProject: OpenProject) -> some View {
        VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
            filesSectionHeader(for: openProject)

            if openProject.document.fonts.count > 1 {
                Text("★ Axis tree source — shared stop layout for all files.")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
                    ForEach(openProject.document.fonts) { font in
                        ProjectInspectorFileRow(
                            font: font,
                            openProject: openProject,
                            isSelected: editor.activeProjectID == openProject.id
                                && editor.selectedFontID == font.id
                        )
                    }

                    Color.clear
                        .frame(height: 8)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: FileChipFrameKey.self,
                                    value: ["\(openProject.id):__end__": geometry.frame(in: .global)]
                                )
                            }
                        }
                }
                .padding(.trailing, StudioSpacing.scrollGutter)
                .padding(.bottom, StudioSpacing.controlGap)
                .onPreferenceChange(FileChipFrameKey.self) { frames in
                    guard !workspaceDrag.isActive else { return }
                    editor.workspaceDrag.setFontChipFrames(frames, source: .inspectorFiles)
                }
            }
            .scrollDisabled(workspaceDrag.isActive)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func filesSectionHeader(for openProject: OpenProject) -> some View {
        HStack(spacing: StudioSpacing.controlGap) {
            StudioSectionLabel(title: "Files")

            Text("\(openProject.document.fonts.count)")
                .font(StudioTypography.meta)
                .foregroundStyle(StudioColors.computedHighlight)

            Spacer(minLength: 0)

            if openProject.document.fonts.count > 1 {
                Button("Save all…") {
                    editor.saveAllFiles(inProjectID: openProject.id)
                }
                .font(StudioTypography.meta)
                .buttonStyle(.plain)
                .disabled(!editor.canSave || editor.isSaveActionBlocked)
            }

            Button {
                editor.presentAddFontPanel(projectID: openProject.id)
            } label: {
                Label("Add font", systemImage: "plus")
            }
            .font(StudioTypography.meta)
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func fileNamingActions(font: FontDocument) -> some View {
        let isMaster = editor.fileRole(for: font.id)?.kind == .master
        let inferEnabled = editor.hasEditableClarifierSlots(for: font.id)
        let showsPush = isMaster && editor.projectHasMultipleFiles
        let showsClear = isMaster
            && editor.projectHasMultipleFiles
            && !editor.clarifierLabels(for: font.id).isEmpty

        HStack(spacing: StudioSpacing.controlGap) {
            Button("Infer") {
                editor.selectFont(id: font.id)
                editor.inferFileClarifiersForSelectedFont()
            }
            .font(StudioTypography.meta)
            .buttonStyle(.plain)
            .disabled(!inferEnabled)
            .help(inferEnabled
                ? "Suggest clarifiers from the filename when axis naming does not already cover them. Uses stop names from the font — never expands abbreviations."
                : "Axis and registration naming already cover this file, or clarifiers belong on variant files.")

            if showsPush {
                Button("Push to tree") {
                    editor.selectFont(id: font.id)
                    editor.pushMasterAxisTreeToAllFonts()
                }
                .font(StudioTypography.meta)
                .buttonStyle(.plain)
                .help("Copy master axis stops to all other files in this project")
            }

            if showsClear {
                Button("Clear") {
                    editor.selectFont(id: font.id)
                    editor.clearFileClarifiers(for: font.id)
                }
                .font(StudioTypography.meta)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}
