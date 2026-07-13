import AppKit
import SwiftUI
import VarFontCore

// MARK: - Modal sheet (Export flow)

struct CommitDiffSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let session: CommitPreflightSession

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            CommitDiffReviewView(session: session, fillsAvailableHeight: true) {
                SaveReviewActionBar(
                    session: session,
                    projectID: session.projectID,
                    includeCancel: true
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .frame(width: 900, height: 680)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared Review actions

private struct SaveReviewActionBar: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let session: CommitPreflightSession
    let projectID: String
    var includeCancel: Bool = false

    private var canExportToRememberedPath: Bool {
        editor.canSaveToRememberedPath(forProjectID: projectID, fontID: session.fontID)
    }

    private var showsExportAll: Bool {
        editor.fontsForSaveReview(projectID: projectID).count > 1
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button("Save Project") {
                editor.saveProject()
            }
            .disabled(!editor.canSaveProject)

            HStack(spacing: 8) {
                if includeCancel {
                    Button("Cancel") {
                        editor.dismissCommitDiffSheet()
                        dismiss()
                    }
                }

                if showsExportAll {
                    Button("Export All…") {
                        editor.saveAllFiles(inProjectID: projectID)
                    }
                    .disabled(!session.preflight.ok || editor.isSaveActionBlocked)
                    .help("Export all files in this project to a folder")
                }

                if canExportToRememberedPath {
                    Button("Export…") {
                        editor.presentSavePanel(for: session)
                    }
                    .disabled(!session.preflight.ok || editor.isSaveActionBlocked)

                    Button("Export") {
                        editor.save(session: session)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.preflight.ok || editor.isSaveActionBlocked)
                    .help("Write to the last export path")
                } else {
                    Button("Export…") {
                        editor.presentSavePanel(for: session)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.preflight.ok || editor.isSaveActionBlocked)
                    .help("Choose a path for the exported font")
                }
            }
        }
    }
}

// MARK: - Review window

private struct SaveReviewFileTabBar: View {
    let projectID: String
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        let fonts = editor.fontsForSaveReview(projectID: projectID)
        if fonts.count > 1 {
            HStack(spacing: StudioSpacing.controlGap) {
                StudioSectionLabel(title: "File")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(fonts) { font in
                            fileChip(font)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func fileChip(_ font: FontDocument) -> some View {
        let isSelected = editor.saveReviewSelectedFontID(forProjectID: projectID) == font.id
        let isLoading = editor.isSaveReviewLoading(forProjectID: projectID, fontID: font.id)

        return Button {
            editor.selectSaveReviewFont(projectID: projectID, fontID: font.id)
        } label: {
            StudioTabChip(isSelected: isSelected) {
                Text(editor.fontBasename(for: font))
                    .font(StudioTypography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
            } trailing: {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!editor.canPreviewSaveReview(forProjectID: projectID, fontID: font.id))
    }
}

struct SaveReviewWindow: View {
    let projectID: String
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismissWindow) private var dismissWindow

    private var selectedFontID: String? {
        editor.saveReviewSelectedFontID(forProjectID: projectID)
    }

    private var session: CommitPreflightSession? {
        editor.saveReviewSession(forProjectID: projectID)
    }

    private var isLoadingCurrentFile: Bool {
        guard let selectedFontID else { return false }
        return editor.isSaveReviewLoading(forProjectID: projectID, fontID: selectedFontID)
    }

    var body: some View {
        VStack(spacing: 0) {
            SaveReviewFileTabBar(projectID: projectID)
            if editor.fontsForSaveReview(projectID: projectID).count > 1 {
                Divider()
            }

            if let session {
                VStack(spacing: 0) {
                    if session.preflight.ok {
                        CommitDiffReviewView(session: session, fillsAvailableHeight: true) {
                            SaveReviewActionBar(session: session, projectID: projectID)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                            SaveReviewActionBar(session: session, projectID: projectID)
                            ScrollView {
                                VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                                    preflightFailureHeader(session: session)
                                    if !session.preflight.errors.isEmpty {
                                        preflightErrorsCard(session.preflight.errors)
                                    }
                                    if !session.preflight.warnings.isEmpty {
                                        preflightWarningsCard(session.preflight.warnings)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            } else if isLoadingCurrentFile {
                VStack(spacing: StudioSpacing.controlGap) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Building review…")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: StudioSpacing.controlGap) {
                    Text("No preview loaded yet.")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        refreshCurrentFile()
                    }
                    .disabled(!canRefreshCurrentFile)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 920, minHeight: 680)
        .preferredColorScheme(.dark)
        .navigationTitle(editor.saveReviewWindowTitle(forProjectID: projectID))
        .background(SaveReviewWindowConfigurator())
        .onAppear(perform: dismissRestoredEmptyWindowIfNeeded)
        .onChange(of: editor.openProjects) { _, projects in
            if !projects.contains(where: { $0.id == projectID }) {
                dismissWindow(id: "save-review", value: projectID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            editor.clearSaveReviewState()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    refreshCurrentFile()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!canRefreshCurrentFile || isLoadingCurrentFile)
                .help("Re-read the font on disk and rebuild the diff")
            }
        }
    }

    private var canRefreshCurrentFile: Bool {
        guard let selectedFontID else { return false }
        return editor.canPreviewSaveReview(forProjectID: projectID, fontID: selectedFontID)
    }

    private func refreshCurrentFile() {
        editor.refreshCommitDiffPreview(forProjectID: projectID, fontID: selectedFontID)
    }

    private func dismissRestoredEmptyWindowIfNeeded() {
        guard session == nil, !isLoadingCurrentFile else { return }
        guard !editor.saveReviewWasExplicitlyOpened(forProjectID: projectID) else { return }
        dismissWindow(id: "save-review", value: projectID)
        SaveReviewWindowLifecycle.closeRestoredWindows()
    }

    private func preflightFailureHeader(session: CommitPreflightSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export preview failed. Check the Review window for details.")
                .font(StudioTypography.emphasis)
            Text("Fix the issues below, then use Refresh to rebuild the diff.")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
            if let code = session.preflight.errors.first?.code {
                Text("Code: \(code)")
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func preflightErrorsCard(_ errors: [CommitError]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cannot export")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                Text(error.message)
                    .font(StudioTypography.caption)
                    .foregroundStyle(StudioColors.errorForeground)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .strokeBorder(StudioColors.errorStroke, lineWidth: 1)
        )
    }

    private func preflightWarningsCard(_ warnings: [PlanWarning]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warnings")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                StudioWarningMessage(message: warning.message)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .strokeBorder(StudioColors.warningStroke, lineWidth: 1)
        )
    }
}

/// Opt out of macOS window restoration for the Review auxiliary window (macOS 14).
private struct SaveReviewWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(window: view.window)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(window: nsView.window)
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier(SaveReviewWindowLifecycle.identifier)
    }
}
