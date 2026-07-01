import SwiftUI
import VarFontCore

struct MainEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @Environment(\.openWindow) private var openWindow
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    @State private var isDropTargeted = false
    @State private var activeDropZone: WorkspaceDropZone = .none
    @State private var openProjectMenuID: String?
    @State private var workspaceOrigin: CGPoint = .zero
    @State private var projectMenuTabRect: CGRect?

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
                .overlay {
                    projectMenuOverlay(screenSize: geometry.size)
                }
                .onDrop(
                    of: EditorViewModel.fontDropTypes,
                    delegate: WorkspaceDropDelegate(
                        isTargeted: $isDropTargeted,
                        activeZone: $activeDropZone,
                        dropHeight: geometry.size.height,
                        isEmptyWorkspace: !editor.hasOpenProjects,
                        isBusy: editor.isBusy,
                        isInternalDragActive: { workspaceDrag.isActive },
                        onDropURLs: { urls, disposition in
                            Task {
                                await editor.importDroppedFonts(urls, disposition: disposition)
                            }
                        }
                    )
                )
                .overlay {
                    if editor.isBusy {
                        loadingOverlay
                    }
                }
                .overlay {
                    if isDropTargeted, !editor.isBusy, !workspaceDrag.isActive {
                        WorkspaceDropOverlay(
                            isEmptyWorkspace: !editor.hasOpenProjects,
                            activeZone: activeDropZone
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)
                .onChange(of: editor.isBusy) { _, busy in
                    if busy {
                        isDropTargeted = false
                        activeDropZone = .none
                    }
                }
        }
        .onKeyPress(.escape) {
            if workspaceDrag.isActive {
                editor.cancelWorkspaceDrag()
                return .handled
            }
            return .ignored
        }
        .sheet(isPresented: pendingDropBinding) {
            ProjectPickerSheet()
                .environmentObject(editor)
        }
        .sheet(item: projectTargetPickerBinding) { mode in
            ProjectTargetPickerSheet(mode: mode)
                .environmentObject(editor)
        }
        .sheet(item: $editor.conflictResolverRequest) { session in
            AxisConflictResolverSheet(bundle: session.bundle)
                .environmentObject(editor)
        }
        .onChange(of: editor.saveReviewOpenRequest) { _, request in
            guard let request else { return }
            openWindow(id: "save-review", value: request.projectID)
        }
        .sheet(isPresented: $editor.presentCommitDiffSheet) {
            if let projectID = editor.activeProjectID,
               let fontID = editor.selectedFontID,
               let session = editor.saveReviewSession(forProjectID: projectID, fontID: fontID) {
                CommitDiffSheet(session: session)
                    .environmentObject(editor)
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
            "Remove project?",
            isPresented: closeProjectConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                editor.confirmCloseProjectAction()
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
    }

    private var pendingDropBinding: Binding<Bool> {
        Binding(
            get: { editor.pendingDropURLs != nil },
            set: { if !$0 { editor.cancelPendingDrop() } }
        )
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

    private var editorChrome: some View {
        VStack(spacing: 0) {
            if editor.hasOpenProjects {
                projectChrome
            }

            Group {
                if editor.hasOpenProjects {
                    StudioPanelSplitView()
                } else if !isDropTargeted {
                    EmptyWorkspaceView()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { toolbarItems }

            if editor.hasOpenProjects {
                editorFooter
            }
        }
        .navigationTitle(activeNavigationTitle)
        .overlayPreferenceValue(ProjectTabAnchorKey.self) { anchors in
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: ProjectMenuTabRectKey.self,
                        value: resolvedProjectMenuTabRect(anchors: anchors, geometry: geometry)
                    )
            }
        }
        .onPreferenceChange(ProjectMenuTabRectKey.self) { rect in
            guard !workspaceDrag.isActive else { return }
            if rect == .zero {
                if openProjectMenuID == nil {
                    projectMenuTabRect = nil
                }
            } else if rect != projectMenuTabRect {
                projectMenuTabRect = rect
            }
        }
    }

    @ViewBuilder
    private func projectMenuOverlay(screenSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if openProjectMenuID != nil, !workspaceDrag.isActive {
                Color.black.opacity(0.001)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture { openProjectMenuID = nil }
            }

            if let openID = openProjectMenuID,
               let tabRect = projectMenuTabRect,
               let openProject = editor.openProjects.first(where: { $0.id == openID }) {
                ProjectDropdownMenu(
                    openProject: openProject,
                    onDismiss: { openProjectMenuID = nil }
                )
                .environmentObject(editor)
                .fixedSize(horizontal: true, vertical: true)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StudioRadius.row))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                .offset(x: tabRect.minX, y: tabRect.maxY + 4)
                .opacity(workspaceDrag.isActive ? 0 : 1)
            }
        }
    }

    private func resolvedProjectMenuTabRect(
        anchors: [String: Anchor<CGRect>],
        geometry: GeometryProxy
    ) -> CGRect {
        guard let openID = openProjectMenuID, let anchor = anchors[openID] else {
            return .zero
        }
        return geometry[anchor]
    }

    private var projectChrome: some View {
        VStack(spacing: 0) {
            ProjectToolbar(openMenuProjectID: $openProjectMenuID)
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
            Button(editor.canSaveToRememberedPathForSelection ? "Save" : "Save Copy…",
                   systemImage: "square.and.arrow.down") {
                if editor.canSaveToRememberedPathForSelection {
                    editor.save()
                } else {
                    editor.saveCopy()
                }
            }
            .disabled(!editor.canSave || editor.isSaveActionBlocked)
            .help(editor.canSaveToRememberedPathForSelection
                ? "Write to the last saved copy path"
                : "Preview and save a patched copy of the font")
        }

        ToolbarItem {
            Button("Save Review", systemImage: "doc.text.magnifyingglass") {
                editor.presentSaveReviewWindow()
            }
            .disabled(!editor.canPreviewSaveReview)
            .help("Open a save review window for the active project")
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
}
