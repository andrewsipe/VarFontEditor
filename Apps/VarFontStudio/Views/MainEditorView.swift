import SwiftUI
import VarFontCore

struct MainEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        editorChrome
            .overlay {
                if editor.isBusy {
                    loadingOverlay
                }
            }
            .fontFileDropTarget()
    }

    private var editorChrome: some View {
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
        .navigationTitle(editor.project?.familyLabel ?? "VarFont Studio")
        .toolbar { toolbarItems }
        .safeAreaInset(edge: .bottom) {
            statusBar
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Button("Open…", systemImage: "folder") {
                editor.presentOpenPanel()
            }
            .help("Open a variable font file")
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
        .background(.bar)
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
    }
}

// MARK: - Drag and drop

private struct FontFileDropTargetModifier: ViewModifier {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: EditorViewModel.fontDropTypes, isTargeted: $isDropTargeted) { providers in
                guard !editor.isBusy else { return false }
                Task {
                    var urls: [URL] = []
                    for provider in providers {
                        if let url = await loadDroppedURL(from: provider) {
                            urls.append(url)
                        }
                    }
                    guard !urls.isEmpty else { return }
                    await editor.importDroppedFonts(urls)
                }
                return true
            }
            .overlay {
                if isDropTargeted, !editor.isBusy {
                    dropOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(StudioTypography.emphasis)
                    .foregroundStyle(.tint)
                Text(editor.project == nil ? "Drop to open font" : "Drop to add font")
                    .font(StudioTypography.bodyMedium)
                Text("TTF, OTF, WOFF, WOFF2")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .allowsHitTesting(false)
    }
}

private extension View {
    func fontFileDropTarget() -> some View {
        modifier(FontFileDropTargetModifier())
    }
}
