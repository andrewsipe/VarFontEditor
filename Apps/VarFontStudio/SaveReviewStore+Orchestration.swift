import AppKit
import Foundation
import UniformTypeIdentifiers
import VarFontCore

extension SaveReviewStore {
    // MARK: - Save Review chrome

    var saveReviewWindowTitle: String {
        guard let activeProjectID = requireHost.activeProjectID else { return "Review" }
        return saveReviewWindowTitle(forProjectID: activeProjectID)
    }

    func saveReviewWindowTitle(forProjectID projectID: String) -> String {
        if let open = requireHost.openProject(for: projectID) {
            return "Review — \(requireHost.projectTabLabel(for: open))"
        }
        return "Review"
    }

    func fontsForSaveReview(projectID: String) -> [FontDocument] {
        requireHost.openProject(for: projectID)?.document.fonts ?? []
    }

    func saveReviewSelectedFontID(forProjectID projectID: String) -> String? {
        if let selected = selectedFontID(projectID: projectID) {
            return selected
        }
        return requireHost.openProject(for: projectID)?.selectedFontID
    }

    func saveReviewSession(forProjectID projectID: String, fontID: String? = nil) -> CommitPreflightSession? {
        guard let fontID = fontID ?? saveReviewSelectedFontID(forProjectID: projectID) else { return nil }
        return session(projectID: projectID, fontID: fontID)
    }

    func saveReviewUIState(forProjectID projectID: String) -> SaveReviewUIState {
        uiState(forProjectID: projectID)
    }

    func updateSaveReviewUIState(forProjectID projectID: String, _ transform: (inout SaveReviewUIState) -> Void) {
        updateUIState(forProjectID: projectID, transform)
    }

    func isSaveReviewLoading(forProjectID projectID: String, fontID: String? = nil) -> Bool {
        isLoading(projectID: projectID, fontID: fontID)
    }

    func selectSaveReviewFont(projectID: String, fontID: String) {
        selectFont(projectID: projectID, fontID: fontID)
        guard canPreviewSaveReview(forProjectID: projectID, fontID: fontID) else { return }
        let projects = requireHost.openProjects
        let isDirty = projects
            .first(where: { $0.id == projectID })?
            .document.fonts.first(where: { $0.id == fontID })?
            .dirty ?? false
        if saveReviewSession(forProjectID: projectID, fontID: fontID) == nil || isDirty {
            refreshCommitDiffPreview(forProjectID: projectID, fontID: fontID)
        }
    }

    func saveReviewWasExplicitlyOpened(forProjectID projectID: String) -> Bool {
        wasExplicitlyOpened(projectID: projectID)
    }

    func presentSaveReviewWindow(forProjectID projectID: String? = nil) {
        let targetID = projectID ?? requireHost.activeProjectID
        guard let targetID else {
            requireHost.postStatusMessage("Open a project first.")
            return
        }
        guard canPreviewSaveReview(forProjectID: targetID) else {
            requireHost.postStatusMessage("Nothing to preview — select a font in this project first.")
            return
        }
        if let fontID = requireHost.selectedFont(forProjectID: targetID)?.id {
            ensureSelectedFont(projectID: targetID, fontID: fontID)
        }
        let fontID = saveReviewSelectedFontID(forProjectID: targetID)
        let hasFreshSession: Bool = {
            guard let fontID,
                  let session = session(projectID: targetID, fontID: fontID),
                  session.preflight.ok,
                  let font = requireHost.font(forProjectID: targetID, fontID: fontID) else {
                return false
            }
            // Rebuild when the project still has unsaved font edits.
            return !font.dirty
        }()
        if !hasFreshSession {
            refreshCommitDiffPreview(forProjectID: targetID, fontID: fontID, presentSheet: false)
        }
        markExplicitlyOpened(projectID: targetID)
        resetUIState(forProjectID: targetID)
        requestOpen(projectID: targetID)
        Task {
            await requireHost.commitService.ensureWorkerReady()
        }
    }

    func toggleSaveReviewWindow(forProjectID projectID: String? = nil) {
        let targetID = projectID ?? requireHost.activeProjectID
        guard let targetID else {
            requireHost.postStatusMessage("Open a project first.")
            return
        }
        if isSaveReviewWindowOpen(forProjectID: targetID) {
            closeSaveReviewWindow(forProjectID: targetID)
            return
        }
        presentSaveReviewWindow(forProjectID: targetID)
    }


    func isSaveReviewWindowOpen(forProjectID projectID: String) -> Bool {
        let title = saveReviewWindowTitle(forProjectID: projectID)
        return NSApplication.shared.windows.contains { window in
            SaveReviewWindowLifecycle.isSaveReviewWindow(window) && window.title == title
        }
    }

    func closeSaveReviewWindow(forProjectID projectID: String) {
        let title = saveReviewWindowTitle(forProjectID: projectID)
        for window in NSApplication.shared.windows where SaveReviewWindowLifecycle.isSaveReviewWindow(window) && window.title == title {
            window.close()
        }
    }

    /// Drop save-review payload when quitting or closing a restored auxiliary window.
    func clearSaveReviewState(forProjectID projectID: String? = nil, fontID: String? = nil) {
        clear(projectID: projectID, fontID: fontID)
    }

    func canPreviewSaveReview(forProjectID projectID: String, fontID: String) -> Bool {
        guard let open = requireHost.openProject(for: projectID),
              open.document.fonts.contains(where: { $0.id == fontID }) else { return false }
        return requireHost.instancePlan(forProjectID: projectID, fontID: fontID) != nil
    }

    func canPreviewSaveReview(forProjectID projectID: String) -> Bool {
        guard let open = requireHost.openProject(for: projectID) else { return false }
        return open.document.fonts.contains { canPreviewSaveReview(forProjectID: projectID, fontID: $0.id) }
    }

    var canPreviewSaveReview: Bool {
        guard let activeProjectID = requireHost.activeProjectID else { return false }
        return canPreviewSaveReview(forProjectID: activeProjectID)
    }

}

extension SaveReviewStore {
    // MARK: - Export / font write path

    func saveCopy() {
        refreshCommitDiffPreview(presentSheet: true)
    }

    func requestSaveToOriginal() {
        guard requireHost.canSave else {
            requireHost.postStatusMessage("Nothing to export — make an edit first.")
            return
        }
        Task {
            guard let projectID = requireHost.activeProjectID, let fontID = requireHost.selectedFontID else { return }
            guard let session = await ensureSaveReviewSession(projectID: projectID, fontID: fontID) else { return }
            guard session.preflight.ok else {
                requireHost.postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
                return
            }
            confirmSaveToOriginal = session
        }
    }

    func confirmSaveToOriginalAction() {
        guard let session = confirmSaveToOriginal,
              let font = requireHost.font(forProjectID: session.projectID, fontID: session.fontID) else { return }
        confirmSaveToOriginal = nil
        Task {
            await performSave(
                session: session,
                to: URL(fileURLWithPath: font.sourcePath),
                inPlace: true
            )
        }
    }

    func saveToOriginalConfirmationMessage(for session: CommitPreflightSession) -> String {
        guard let font = requireHost.font(forProjectID: session.projectID, fontID: session.fontID) else {
            return "Overwrite the original font file? This cannot be undone."
        }
        return "Overwrite \(URL(fileURLWithPath: font.sourcePath).lastPathComponent)? A .vfstudio-backup copy is written beside the original first."
    }

    /// User-facing: Export — write to `font.outputPath` when set; otherwise open Review (same as Export…).
    func save() {
        guard requireHost.canSave else {
            requireHost.postStatusMessage("Nothing to export — make an edit first.")
            return
        }
        Task {
            await saveActiveFontUsingRememberedPathOrReview()
        }
    }

    func canSaveToRememberedPath(forProjectID projectID: String, fontID: String) -> Bool {
        rememberedOutputURL(forProjectID: projectID, fontID: fontID) != nil
    }

    var canSaveToRememberedPathForSelection: Bool {
        guard let projectID = requireHost.activeProjectID, let fontID = requireHost.selectedFontID else { return false }
        return canSaveToRememberedPath(forProjectID: projectID, fontID: fontID)
    }

    func savedOutputLabel(for font: FontDocument) -> String? {
        guard let outputPath = font.outputPath else { return nil }
        return URL(fileURLWithPath: outputPath).lastPathComponent
    }

    private func rememberedOutputURL(forProjectID projectID: String, fontID: String) -> URL? {
        guard let font = requireHost.font(forProjectID: projectID, fontID: fontID),
              let path = font.outputPath else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        let parent = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    @MainActor
    private func saveActiveFontUsingRememberedPathOrReview() async {
        guard let projectID = requireHost.activeProjectID, let fontID = requireHost.selectedFontID else { return }

        if let outputURL = rememberedOutputURL(forProjectID: projectID, fontID: fontID),
           let font = requireHost.font(forProjectID: projectID, fontID: fontID) {
            guard let session = await ensureSaveReviewSession(projectID: projectID, fontID: fontID) else { return }
            guard session.preflight.ok else {
                requireHost.postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
                return
            }
            if EditorViewModel.normalizedPath(outputURL) == EditorViewModel.normalizedPath(URL(fileURLWithPath: font.sourcePath)) {
                confirmSaveToOriginal = session
                return
            }
            await performSave(session: session, to: outputURL)
            return
        }

        saveCopy()
    }

    @MainActor
    func ensureSaveReviewSession(
        projectID: String,
        fontID: String,
        preferWorker: Bool = true
    ) async -> CommitPreflightSession? {
        if let session = saveReviewSession(forProjectID: projectID, fontID: fontID),
           session.preflight.ok {
            return session
        }
        return await refreshCommitDiffPreviewAsync(
            forProjectID: projectID,
            fontID: fontID,
            preferWorker: preferWorker
        )
    }

    @discardableResult
    @MainActor
    func refreshCommitDiffPreviewAsync(
        forProjectID projectID: String? = nil,
        fontID: String? = nil,
        presentSheet: Bool = false,
        preferWorker: Bool = true
    ) async -> CommitPreflightSession? {
        let targetProjectID = projectID ?? requireHost.activeProjectID
        guard let targetProjectID,
              let open = requireHost.openProject(for: targetProjectID) else {
            if presentSheet {
                requireHost.postStatusMessage("Nothing to save — open a font first.")
            }
            return nil
        }

        let targetFontID = fontID
            ?? saveReviewSelectedFontID(forProjectID: targetProjectID)
            ?? open.selectedFontID
        guard let targetFontID,
              let font = open.document.fonts.first(where: { $0.id == targetFontID }),
              let plan = requireHost.instancePlan(forProjectID: targetProjectID, fontID: targetFontID) else {
            if presentSheet {
                requireHost.postStatusMessage("Nothing to save — open a font first.")
            }
            return nil
        }

        let projectDoc = open.document

        let duplicateIncluded = plan.instances.filter { $0.included && $0.duplicate }
        if !duplicateIncluded.isEmpty {
            requireHost.postStatusMessage("Resolve duplicate instance names before saving.")
            return nil
        }

        guard FileManager.default.fileExists(atPath: font.sourcePath) else {
            requireHost.postStatusMessage("Source font file is missing — re-open the original file.")
            return nil
        }

        let bookmark = requireHost.sourceBookmarks[font.id]
        let outputPath = font.outputPath ?? CommitRequestBuilder.suggestedOutputPath(for: font.sourcePath)
        var dryRunRequest = CommitRequestBuilder.make(
            font: font,
            naming: projectDoc.naming,
            plan: plan,
            outputPath: outputPath,
            dryRun: true,
            nameidStrategy: projectDoc.nameidStrategy
        )

        beginLoading(projectID: targetProjectID, fontID: targetFontID)
        defer { endLoading(projectID: targetProjectID, fontID: targetFontID) }

        do {
            if preferWorker {
                await requireHost.commitService.ensureWorkerReady()
            }
            let bookmarkData = bookmark
            let sourcePath = font.sourcePath
            let cacheFontID = font.id
            let analysisAndHelper = try await Task.detached(priority: .userInitiated) {
                let analysis = try SourceFontAccess.withReadableSourceURL(
                    bookmark: bookmarkData,
                    fallbackPath: sourcePath
                ) { sourceURL in
                    try FontAnalysisReader.analyzeForCommitDiff(url: sourceURL)
                }
                let helperSourcePath = try SourceFontAccess.helperSourcePath(
                    bookmark: bookmarkData,
                    fallbackPath: sourcePath,
                    fontID: cacheFontID
                )
                return (analysis, helperSourcePath)
            }.value
            let analysis = analysisAndHelper.0
            let helperSourcePath = analysisAndHelper.1
            dryRunRequest.sourcePath = helperSourcePath
            let result = try await requireHost.commitService.commit(dryRunRequest, preferWorker: preferWorker)
            if result.ok {
                let diffReport = CommitDiffBuilder.build(
                    analysis: analysis,
                    font: font,
                    plan: plan,
                    result: result
                )
                let presentation = SaveReviewPresentationBuilder.build(
                    analysis: analysis,
                    font: font,
                    plan: plan,
                    report: diffReport,
                    diff: result.diff
                )
                var writeRequest = CommitRequestBuilder.make(
                    font: font,
                    naming: projectDoc.naming,
                    plan: plan,
                    outputPath: outputPath,
                    dryRun: false,
                    nameidStrategy: projectDoc.nameidStrategy
                )
                writeRequest.sourcePath = helperSourcePath
                let session = CommitPreflightSession(
                    projectID: targetProjectID,
                    fontID: font.id,
                    dryRunRequest: dryRunRequest,
                    baseRequest: writeRequest,
                    preflight: result,
                    diffReport: diffReport,
                    presentation: presentation,
                    informationalNotes: OpenTypeAxisAudit.allInformationalMessages(
                        analysis: analysis,
                        font: font
                    )
                )
                storeSession(session, projectID: targetProjectID, fontID: font.id)
                if presentSheet {
                    presentCommitDiffSheet = true
                }
                return session
            }
            let message = result.errors.first?.message ?? "Export preview failed. Check the Review window for details."
            var writeRequest = CommitRequestBuilder.make(
                font: font,
                naming: projectDoc.naming,
                plan: plan,
                outputPath: outputPath,
                dryRun: false,
                nameidStrategy: projectDoc.nameidStrategy
            )
            writeRequest.sourcePath = dryRunRequest.sourcePath
            let failedSession = CommitPreflightSession(
                projectID: targetProjectID,
                fontID: font.id,
                dryRunRequest: dryRunRequest,
                baseRequest: writeRequest,
                preflight: result,
                diffReport: CommitDiffBuilder.empty,
                presentation: .empty,
                informationalNotes: []
            )
            storeSession(failedSession, projectID: targetProjectID, fontID: font.id)
            requireHost.postStatusMessage(message)
            if presentSheet {
                presentCommitDiffSheet = true
            }
            return failedSession
        } catch {
            requireHost.postSaveFailure(commitFailureMessage(error))
            return nil
        }
    }

    func dismissCommitDiffSheet() {
        dismissSheet()
    }

    /// Re-read the source font and run vfcommit dry-run to build the save review diff.
    func refreshCommitDiffPreview(
        forProjectID projectID: String? = nil,
        fontID: String? = nil,
        presentSheet: Bool = false
    ) {
        Task {
            await refreshCommitDiffPreviewAsync(
                forProjectID: projectID,
                fontID: fontID,
                presentSheet: presentSheet
            )
        }
    }

    func exportCommitJSON(session: CommitPreflightSession) {
        let panel = NSOpenPanel()
        panel.title = "Export Commit JSON"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for CommitRequest, CommitResult, and CommitDiffReport JSON files."

        panel.begin { [weak self] response in
            guard response == .OK, let directory = panel.url else { return }
            Task { @MainActor in
                self?.writeCommitJSON(session: session, to: directory)
            }
        }
    }

    private func writeCommitJSON(session: CommitPreflightSession, to directory: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        do {
            try encoder.encode(session.dryRunRequest).write(
                to: directory.appendingPathComponent("\(stamp)-commit-request.json")
            )
            try encoder.encode(session.preflight).write(
                to: directory.appendingPathComponent("\(stamp)-commit-result.json")
            )
            try encoder.encode(session.diffReport).write(
                to: directory.appendingPathComponent("\(stamp)-commit-diff-report.json")
            )
            requireHost.postStatusMessage("Exported save plan to \(directory.lastPathComponent)")
        } catch {
            requireHost.postStatusMessage("JSON export failed: \(error.localizedDescription)")
        }
    }

    func presentSavePanel(for session: CommitPreflightSession) {
        guard let font = requireHost.font(forProjectID: session.projectID, fontID: session.fontID) else { return }

        let panel = NSSavePanel()
        panel.title = "Export Font"
        panel.canCreateDirectories = true
        // Suggest -patched beside the source so same-folder export doesn't collide with the original.
        // User can rename or pick another folder; macOS warns if the chosen name already exists.
        let suggested = CommitRequestBuilder.suggestedOutputPath(for: font.sourcePath)
        let suggestedURL = URL(fileURLWithPath: suggested)
        panel.nameFieldStringValue = suggestedURL.lastPathComponent
        let sourceURL = URL(fileURLWithPath: font.sourcePath)
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        let ext = sourceURL.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let normalizedOutput = EditorViewModel.normalizedPath(url)
            let normalizedSource = EditorViewModel.normalizedPath(URL(fileURLWithPath: font.sourcePath))
            if normalizedOutput == normalizedSource {
                self?.confirmSaveToOriginal = session
                return
            }
            Task { @MainActor in
                await self?.performSave(session: session, to: url)
            }
        }
    }

    func save(session: CommitPreflightSession) {
        Task {
            await save(session: session, usingRememberedPath: true)
        }
    }

    @MainActor
    private func save(session: CommitPreflightSession, usingRememberedPath: Bool) async {
        guard session.preflight.ok else {
            requireHost.postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
            return
        }

        if usingRememberedPath,
           let url = rememberedOutputURL(forProjectID: session.projectID, fontID: session.fontID),
           let font = requireHost.font(forProjectID: session.projectID, fontID: session.fontID) {
            if EditorViewModel.normalizedPath(url) == EditorViewModel.normalizedPath(URL(fileURLWithPath: font.sourcePath)) {
                confirmSaveToOriginal = session
                return
            }
            await performSave(session: session, to: url)
            return
        }

        presentSavePanel(for: session)
    }

    func saveAllFiles(inProjectID projectID: String? = nil) {
        Task {
            await saveAllFilesAsync(inProjectID: projectID)
        }
    }

    @MainActor
    private func saveAllFilesAsync(inProjectID projectID: String? = nil) async {
        guard let projectID = projectID ?? requireHost.activeProjectID,
              let open = requireHost.openProject(for: projectID) else { return }

        let fontsToWrite = open.document.fonts.filter(\.dirty)
        let targets = fontsToWrite.isEmpty ? open.document.fonts : fontsToWrite
        guard !targets.isEmpty else {
            requireHost.postStatusMessage("Nothing to export.")
            return
        }

        for font in targets {
            guard let plan = requireHost.instancePlan(forProjectID: projectID, fontID: font.id) else {
                requireHost.postStatusMessage("Couldn't prepare the export preview. Try again, or check that the font file hasn't moved or changed.")
                return
            }
            if plan.instances.contains(where: { $0.included && $0.duplicate }) {
                requireHost.postStatusMessage("Resolve duplicate instance names in \(requireHost.fontBasename(for: font)) before saving.")
                return
            }
        }

        var sessions: [String: CommitPreflightSession] = [:]
        await withTaskGroup(of: (String, CommitPreflightSession?).self) { group in
            for font in targets {
                let fontID = font.id
                group.addTask { @MainActor in
                    let session = await self.ensureSaveReviewSession(
                        projectID: projectID,
                        fontID: fontID,
                        preferWorker: false
                    )
                    return (fontID, session)
                }
            }
            for await (fontID, session) in group {
                sessions[fontID] = session
            }
        }

        for font in targets {
            guard let session = sessions[font.id] else {
                requireHost.postStatusMessage("Export preview failed for \(requireHost.fontBasename(for: font)). Check the Review window for details.")
                return
            }
            guard session.preflight.ok else {
                requireHost.postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
                return
            }
        }

        var outputURLs: [String: URL] = [:]
        for font in targets {
            if let url = rememberedOutputURL(forProjectID: projectID, fontID: font.id) {
                if url.path == font.sourcePath {
                    requireHost.postStatusMessage("Export All cannot overwrite originals — use Export to Original… per file.")
                    return
                }
                outputURLs[font.id] = url
            }
        }

        var outputDirectory: URL?
        if targets.contains(where: { outputURLs[$0.id] == nil }) {
            guard let directory = await chooseOutputDirectory(
                title: "Export Fonts",
                message: "Choose a folder. Fonts keep their original filenames."
            ) else { return }
            outputDirectory = directory
            for font in targets where outputURLs[font.id] == nil {
                outputURLs[font.id] = URL(
                    fileURLWithPath: CommitRequestBuilder.packageOutputPath(
                        for: font.sourcePath,
                        in: directory
                    )
                )
            }
        }

        for font in targets {
            guard let url = outputURLs[font.id] else { continue }
            if EditorViewModel.normalizedPath(url) == EditorViewModel.normalizedPath(URL(fileURLWithPath: font.sourcePath)) {
                requireHost.postStatusMessage("Export All cannot overwrite originals — use Export to Original… per file.")
                return
            }
        }

        requireHost.isBusy = true
        defer { requireHost.isBusy = false }

        for font in targets {
            guard let session = sessions[font.id], let url = outputURLs[font.id] else { continue }
            await performSave(session: session, to: url, manageBusyState: false)
        }

        let folderLabel = outputDirectory?.lastPathComponent
            ?? outputURLs.values.first?.deletingLastPathComponent().lastPathComponent
            ?? "output folder"
        requireHost.postStatusMessage("Exported \(targets.count) fonts to \(folderLabel)")
    }

    private func chooseOutputDirectory(title: String, message: String) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = title
            panel.message = message
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Choose Folder"
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    var isSaveActionBlocked: Bool {
        if requireHost.isBusy { return true }
        guard let projectID = requireHost.activeProjectID else { return false }
        return isSaveReviewLoading(forProjectID: projectID)
    }

    func performSave(
        session: CommitPreflightSession,
        to outputURL: URL,
        inPlace: Bool = false,
        manageBusyState: Bool = true
    ) async {
        guard let projectIndex = requireHost.openProjects.firstIndex(where: { $0.id == session.projectID }),
              let fontIndex = requireHost.openProjects[projectIndex].document.fonts.firstIndex(where: { $0.id == session.fontID }) else {
            return
        }

        let originalSourcePath = requireHost.openProjects[projectIndex].document.fonts[fontIndex].sourcePath
        guard FileManager.default.fileExists(atPath: originalSourcePath) else {
            requireHost.postStatusMessage("Source font file is missing — re-open the original file.")
            return
        }

        var request = session.baseRequest
        request.outputPath = outputURL.path
        request.originalSourcePath = originalSourcePath
        request.allowInPlace = inPlace
        request.dryRun = false
        request.requestID = UUID().uuidString.lowercased()

        if manageBusyState { requireHost.isBusy = true }
        defer { if manageBusyState { requireHost.isBusy = false } }

        do {
            let result = try await requireHost.commitService.commit(request)
            guard result.ok else {
                let message = result.errors.first?.message ?? "Export failed."
                requireHost.postStatusMessage(message)
                return
            }

            var project = requireHost.openProjects[projectIndex].document
            if inPlace {
                SourceFontAccess.invalidateCache(fontID: session.fontID)
                let sourceURL = URL(fileURLWithPath: originalSourcePath)
                requireHost.registerSourceBookmark(url: sourceURL, fontID: session.fontID)
                project.fonts[fontIndex].outputPath = originalSourcePath
            } else {
                project.fonts[fontIndex].outputPath = outputURL.path
            }
            project.fonts[fontIndex].dirty = false
            requireHost.openProjects[projectIndex].document = project
            requireHost.publishOpenProjects()
            if requireHost.activeProjectID == session.projectID {
                requireHost.project = project
                requireHost.refreshCanSave()
            }
            clearSaveReviewState(forProjectID: session.projectID, fontID: session.fontID)
            dismissSheet()

            if inPlace {
                let backupName = URL(fileURLWithPath: originalSourcePath).lastPathComponent + ".vfstudio-backup"
                requireHost.postStatusMessage("Saved to original (backup: \(backupName))")
            } else if let count = result.summary?.instancesWritten {
                requireHost.postStatusMessage("Saved \(count) instances to \(outputURL.lastPathComponent)")
            } else {
                requireHost.postStatusMessage("Saved \(outputURL.lastPathComponent)")
            }
        } catch {
            requireHost.postSaveFailure(commitFailureMessage(error))
        }
    }

    private func commitFailureMessage(_ error: Error) -> String {
        let userFacingSaveEngineMessage = "Couldn't write the font — the save engine isn't installed. Reinstall VarFont Studio."
        switch error {
        case CommitServiceError.helperNotFound:
            #if DEBUG
            print("Save helper not found — vfcommit.py is missing from Tools/vfcommit.")
            #endif
            return userFacingSaveEngineMessage
        case let CommitServiceError.helperUnavailable(path):
            #if DEBUG
            print("Save helper unavailable at \(path).")
            #endif
            return userFacingSaveEngineMessage
        case let CommitServiceError.helperFailed(detail):
            #if DEBUG
            print("Save helper failed: \(detail)")
            #endif
            return "Couldn't write the font. \(detail)"
        case let CommitServiceError.invalidHelperOutput(detail):
            #if DEBUG
            print("Save helper returned invalid output: \(detail)")
            #endif
            if detail.localizedCaseInsensitiveContains("fonttools")
                || detail.localizedCaseInsensitiveContains("fontTools")
            {
                return userFacingSaveEngineMessage
            }
            return "Couldn't write the font. \(detail)"
        default:
            return "Export failed: \(error.localizedDescription)"
        }
    }
}
