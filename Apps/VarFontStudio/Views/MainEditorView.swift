import SwiftUI
import VarFontCore

struct MainEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @Environment(\.openWindow) private var openWindow
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    @State private var isDropTargeted = false
    @State private var workspaceOrigin: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            editorChrome
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onAppear {
                    workspaceOrigin = geometry.frame(in: .global).origin
                }
                .onChange(of: geometry.size) { _, _ in
                    workspaceOrigin = geometry.frame(in: .global).origin
                }
                .overlay {
                    WorkspaceDragGhostOverlay(workspaceOrigin: workspaceOrigin)
                        .allowsHitTesting(false)
                }
                .onDrop(
                    of: EditorViewModel.fontDropTypes,
                    delegate: WorkspaceDropDelegate(
                        isTargeted: $isDropTargeted,
                        globalOrigin: geometry.frame(in: .global).origin,
                        isBusy: editor.isBusy,
                        activeProjectID: editor.activeProjectID,
                        isInternalDragActive: { workspaceDrag.isActive },
                        coordinator: workspaceDrag,
                        onDropURLs: { urls, target in
                            Task {
                                await editor.importDroppedFonts(urls, target: target)
                            }
                        }
                    )
                )
                .overlay {
                    if editor.isBusy {
                        loadingOverlay
                    }
                }
                .onChange(of: editor.isBusy) { _, busy in
                    if busy {
                        isDropTargeted = false
                        workspaceDrag.cancelExternalFileDrop()
                    }
                }
        }
        .onKeyPress(.escape) {
            if workspaceDrag.isActive {
                editor.cancelWorkspaceDrag()
                return .handled
            }
            if workspaceDrag.isExternalFileDropActive {
                workspaceDrag.cancelExternalFileDrop()
                isDropTargeted = false
                return .handled
            }
            return .ignored
        }
        .sheet(item: projectTargetPickerBinding) { mode in
            ProjectTargetPickerSheet(mode: mode)
                .environmentObject(editor)
        }
        .sheet(item: $editor.conflictResolverRequest) { session in
            AxisConflictResolverSheet(
                bundle: session.bundle,
                reviewPosition: session.reviewPosition,
                reviewTotal: session.reviewTotal
            )
            .environmentObject(editor)
            .preferredColorScheme(.dark)
        }
        .sheet(item: $editor.planIssueResolverRequest) { session in
            PlanIssueResolverSheet(
                warning: session.warning,
                reviewPosition: session.reviewPosition,
                reviewTotal: session.reviewTotal
            )
            .environmentObject(editor)
            .preferredColorScheme(.dark)
            // Forces a fresh view (and fresh @State) per session — "Apply and continue" swaps
            // one non-nil sheet item for another, and SwiftUI won't re-run onAppear for that
            // transition unless the view's identity actually changes.
            .id(session.id)
        }
        .onChange(of: editor.saveReviewOpenRequest) { _, request in
            guard let request else { return }
            openWindow(id: "save-review", value: request.projectID)
        }
        .sheet(isPresented: $editor.presentCommitDiffSheet) {
            if let projectID = editor.activeProjectID,
               let fontID = editor.selectedFontID {
                if let session = editor.saveReviewSession(forProjectID: projectID, fontID: fontID) {
                    CommitDiffSheet(session: session)
                        .environmentObject(editor)
                } else if editor.isSaveReviewLoading(forProjectID: projectID, fontID: fontID) {
                    saveReviewSheetLoadingState
                } else {
                    saveReviewSheetErrorState
                }
            } else {
                saveReviewSheetErrorState
            }
        }
        .sheet(isPresented: $editor.showShortcutsHelp) {
            StudioShortcutsHelpView()
        }
        .sheet(item: $editor.missingFontsRequest) { _ in
            MissingFontsSheet()
                .environmentObject(editor)
        }
        .confirmationDialog(
            "Overwrite original font?",
            isPresented: saveToOriginalConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) {
                editor.confirmSaveToOriginalAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmSaveToOriginal = nil
            }
        } message: {
            if let session = editor.confirmSaveToOriginal {
                Text(editor.saveToOriginalConfirmationMessage(for: session))
            }
        }
        .confirmationDialog(
            "Remove font?",
            isPresented: removeFontConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                editor.confirmRemoveFontAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmRemoveFont = nil
            }
        } message: {
            if let request = editor.confirmRemoveFont {
                Text(editor.removeFontConfirmationMessage(for: request))
            }
        }
        .confirmationDialog(
            "Close Project?",
            isPresented: closeProjectConfirmBinding,
            titleVisibility: .visible
        ) {
            if let projectID = editor.confirmCloseProjectID,
               editor.projectNeedsProjectFileSave(projectID: projectID) {
                Button("Save Project") {
                    editor.confirmCloseProjectSaveAction()
                }
            }
            Button("Discard", role: .destructive) {
                editor.confirmCloseProjectDiscardAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmCloseProjectID = nil
            }
        } message: {
            if let projectID = editor.confirmCloseProjectID {
                Text(editor.closeProjectConfirmationMessage(for: projectID))
            }
        }
        .confirmationDialog(
            "Quit VarFont Studio?",
            isPresented: $editor.confirmQuitRequested,
            titleVisibility: .visible
        ) {
            if editor.canSaveProjectOnQuit {
                Button("Save Project") {
                    editor.confirmQuitSaveProjectAction()
                }
            }
            Button("Discard", role: .destructive) {
                editor.confirmQuitDiscardAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmQuitCancelAction()
            }
        } message: {
            Text(editor.quitConfirmationMessage())
        }
        .confirmationDialog(
            "Move font?",
            isPresented: moveFontConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Move") {
                editor.confirmMoveFontAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmMoveFont = nil
            }
        } message: {
            if let request = editor.confirmMoveFont {
                Text(editor.moveFontConfirmationMessage(for: request))
            }
        }
        .confirmationDialog(
            "Combine projects?",
            isPresented: combineProjectsConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Combine", role: .destructive) {
                editor.confirmCombineProjectsAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmCombineProjects = nil
            }
        } message: {
            if let request = editor.confirmCombineProjects {
                Text(editor.combineProjectsConfirmationMessage(for: request))
            }
        }
        .confirmationDialog(
            "Move to new project?",
            isPresented: splitFontConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Move") {
                editor.confirmSplitFontAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmSplitFont = nil
            }
        } message: {
            if let request = editor.confirmSplitFont {
                Text(editor.splitFontConfirmationMessage(for: request))
            }
        }
        .confirmationDialog(
            "Set as Master?",
            isPresented: setAsMasterConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Set as Master", role: .destructive) {
                editor.confirmSetAsMasterAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmSetAsMasterFontID = nil
            }
        } message: {
            Text("This file will become the shared axis-tree source for this project.")
        }
        .confirmationDialog(
            "Push to Tree?",
            isPresented: $editor.confirmPushAxisTree,
            titleVisibility: .visible
        ) {
            Button("Push", role: .destructive) {
                editor.confirmPushAxisTreeAction()
            }
            Button("Cancel", role: .cancel) {
                editor.confirmPushAxisTree = false
            }
        } message: {
            Text(editor.pushAxisTreeConfirmationMessage())
        }
        .onChange(of: editor.instanceSearchFocusToken) { _, token in
            guard token != nil else { return }
            layout.showInstances = true
        }
    }

    private var projectTargetPickerBinding: Binding<ProjectTargetPickerMode?> {
        Binding(
            get: { editor.projectTargetPickerMode },
            set: { editor.projectTargetPickerMode = $0 }
        )
    }

    private var removeFontConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmRemoveFont != nil },
            set: { if !$0 { editor.confirmRemoveFont = nil } }
        )
    }

    private var saveToOriginalConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmSaveToOriginal != nil },
            set: { if !$0 { editor.confirmSaveToOriginal = nil } }
        )
    }

    private var closeProjectConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmCloseProjectID != nil },
            set: { if !$0 { editor.confirmCloseProjectID = nil } }
        )
    }

    private var moveFontConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmMoveFont != nil },
            set: { if !$0 { editor.confirmMoveFont = nil } }
        )
    }

    private var combineProjectsConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmCombineProjects != nil },
            set: { if !$0 { editor.confirmCombineProjects = nil } }
        )
    }

    private var splitFontConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmSplitFont != nil },
            set: { if !$0 { editor.confirmSplitFont = nil } }
        )
    }

    private var setAsMasterConfirmBinding: Binding<Bool> {
        Binding(
            get: { editor.confirmSetAsMasterFontID != nil },
            set: { if !$0 { editor.confirmSetAsMasterFontID = nil } }
        )
    }

    private var editorChrome: some View {
        VStack(spacing: 0) {
            if let error = editor.persistentSaveError {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cannot export")
                            .font(StudioTypography.sectionLabel)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(StudioTypography.caption)
                            .foregroundStyle(StudioColors.errorForeground)
                    }
                    Spacer(minLength: 0)
                    Button {
                        editor.dismissPersistentSaveError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .strokeBorder(StudioColors.errorStroke, lineWidth: 1)
                )
                .padding(.horizontal, StudioSpacing.panelHorizontal)
                .padding(.top, 8)
            }

            if editor.hasOpenProjects {
                projectChrome
            }

            Group {
                if editor.hasOpenProjects {
                    StudioPanelSplitView()
                } else {
                    EmptyWorkspaceView(isDropTargeted: isDropTargeted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { toolbarItems }

            if editor.hasOpenProjects {
                editorFooter
            }
        }
        .navigationTitle(activeNavigationTitle)
    }

    private var projectChrome: some View {
        VStack(spacing: 0) {
            ProjectToolbar()
                .environmentObject(editor)

            ProjectFileSubBar()
                .environmentObject(editor)

            Divider()
        }
        .background(.bar)
    }

    private var activeNavigationTitle: String {
        if let id = editor.activeProjectID,
           let openProject = editor.openProjects.first(where: { $0.id == id }) {
            return editor.projectTabLabel(for: openProject)
        }
        return "VarFont Studio"
    }

    /// Bottom chrome: naming-order chain + status row.
    private var editorFooter: some View {
        VStack(spacing: 0) {
            Divider()
            NamingOrderChainFooter()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, StudioSpacing.sectionGap - 2)
            Divider()
            statusBar
        }
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button("Open…", systemImage: "folder") {
                editor.presentOpenPanel()
            }
            .help("Open a variable font — creates a new project tab")
        }

        ToolbarItem {
            Button("Save Project", systemImage: "square.and.arrow.down.on.square") {
                editor.saveProject()
            }
            .disabled(!editor.canSaveProject)
            .help("Save the project file")
        }

        ToolbarItem {
            Button(editor.canSaveToRememberedPathForSelection ? "Export" : "Export…",
                   systemImage: "square.and.arrow.up") {
                if editor.canSaveToRememberedPathForSelection {
                    editor.save()
                } else {
                    editor.saveCopy()
                }
            }
            .disabled(!editor.canSave || editor.isSaveActionBlocked)
            .help(editor.canSaveToRememberedPathForSelection
                ? "Write to the last export path"
                : "Preview and export a patched copy of the font")
        }

        ToolbarItem {
            Button("Review…", systemImage: "doc.text.magnifyingglass") {
                editor.presentSaveReviewWindow()
            }
            .disabled(!editor.canPreviewSaveReview)
            .help("Open a review window for the active project")
        }
    }

    private var statusBar: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            HStack(spacing: StudioSpacing.controlGap) {
                if let id = editor.activeProjectID,
                   let openProject = editor.openProjects.first(where: { $0.id == id }) {
                    Text(editor.projectTabLabel(for: openProject))
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if editor.selectedFont != nil {
                        Text("|")
                            .font(StudioTypography.meta)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let font = editor.selectedFont {
                    Text(editor.fontBasename(for: font))
                        .font(StudioTypography.meta)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: StudioSpacing.controlGap)

            if let message = editor.statusMessage {
                Text(message)
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
        .padding(.vertical, StudioSpacing.toolbarVertical)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(spacing: StudioSpacing.controlGap + 2) {
                Label("VarFont Studio", systemImage: "textformat.size")
                    .font(StudioTypography.emphasis)
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StudioRadius.row))
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private var saveReviewSheetLoadingState: some View {
        VStack(spacing: StudioSpacing.sectionGap) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading review…")
                .font(StudioTypography.body)
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 180)
        .preferredColorScheme(.dark)
    }

    private var saveReviewSheetErrorState: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Review")
                .font(StudioTypography.emphasis)
            Text("Couldn't load the review preview. Try again from Export… or the Review window.")
                .font(StudioTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Dismiss") {
                    editor.dismissCommitDiffSheet()
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .preferredColorScheme(.dark)
    }
}
