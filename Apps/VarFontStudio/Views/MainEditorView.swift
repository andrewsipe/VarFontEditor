import SwiftUI
import VarFontCore

struct MainEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isDropTargeted = false
    @State private var activeDropZone: WorkspaceDropZone = .none
    @State private var openProjectMenuID: String?

    var body: some View {
        GeometryReader { geometry in
            editorChrome
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onDrop(
                    of: EditorViewModel.fontDropTypes,
                    delegate: WorkspaceDropDelegate(
                        isTargeted: $isDropTargeted,
                        activeZone: $activeDropZone,
                        dropHeight: geometry.size.height,
                        isEmptyWorkspace: !editor.hasOpenProjects,
                        isBusy: editor.isBusy,
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
                    if isDropTargeted, !editor.isBusy {
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
        .sheet(isPresented: pendingDropBinding) {
            ProjectPickerSheet()
                .environmentObject(editor)
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
            Text("This file has unsaved changes.")
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
            Text("One or more files in this project have unsaved changes.")
        }
    }

    private var pendingDropBinding: Binding<Bool> {
        Binding(
            get: { editor.pendingDropURLs != nil },
            set: { if !$0 { editor.cancelPendingDrop() } }
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

    private var editorChrome: some View {
        VStack(spacing: 0) {
            ProjectToolbar(openMenuProjectID: $openProjectMenuID)
                .environmentObject(editor)

            ProjectFileSubBar()
                .environmentObject(editor)

            Group {
                if editor.hasOpenProjects {
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        AxisTreePanel()
                            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
                    } content: {
                        InstanceListPanel()
                            .navigationSplitViewColumnWidth(min: 320, ideal: 420)
                    } detail: {
                        InspectorPanel()
                            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                    }
                } else if !isDropTargeted {
                    EmptyWorkspaceView()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(activeNavigationTitle)
            .toolbar { toolbarItems }

            if editor.hasOpenProjects {
                editorFooter
            }
        }
        .overlayPreferenceValue(ProjectTabAnchorKey.self) { anchors in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if openProjectMenuID != nil {
                        Color.black.opacity(0.001)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture { openProjectMenuID = nil }
                    }

                    if let openID = openProjectMenuID,
                       let openProject = editor.openProjects.first(where: { $0.id == openID }),
                       let anchor = anchors[openID] {
                        let tabRect = geometry[anchor]
                        ProjectDropdownMenu(
                            openProject: openProject,
                            onDismiss: { openProjectMenuID = nil }
                        )
                        .environmentObject(editor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 360, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StudioRadius.row))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                        .offset(x: tabRect.minX, y: tabRect.maxY + 4)
                    }
                }
            }
        }
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
            .help("New project — open a variable font")
        }

        ToolbarItem {
            Button("Save Copy…", systemImage: "square.and.arrow.down") {
                editor.saveCopy()
            }
            .disabled(!editor.canSave)
            .help("Write patched font (not yet implemented)")
        }
    }

    private var statusBar: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            if let id = editor.activeProjectID,
               let openProject = editor.openProjects.first(where: { $0.id == id }) {
                Text(editor.projectTabLabel(for: openProject))
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let font = editor.selectedFont {
                Text(editor.fontBasename(for: font))
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let message = editor.statusMessage {
                Text(message)
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
        .padding(.vertical, 4)
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
