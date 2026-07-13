import AppKit
import Combine
import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import VarFontCore

enum InstanceFilter: String, CaseIterable, Identifiable {
    case all
    case included
    case excluded
    case duplicates

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .included: "Included"
        case .excluded: "Excluded"
        case .duplicates: "Duplicates"
        }
    }
}

struct InstanceGroup: Identifiable, Equatable {
    var label: String
    var instances: [PlannedInstance]

    var id: String { label }
}

struct InstanceListDisplay: Equatable {
    static let empty = InstanceListDisplay()

    var groups: [InstanceGroup] = []
    var isEmpty: Bool = true
    var summary: String?
    var axisStopFilterLabel: String?
    var coordCaptions: [String: String] = [:]
    var includedByKey: [String: Bool] = [:]
}

struct AxisTreeFocusRequest: Equatable {
    let axisTag: String
    let stopID: String
    let token: UUID
}

struct AxisConflictResolverSession: Identifiable {
    let id = UUID()
    let bundle: AxisConflictBundle
    let reviewPosition: Int?
    let reviewTotal: Int?
}

struct PlanIssueResolverSession: Identifiable {
    let id = UUID()
    let warning: PlanWarning
    let reviewPosition: Int?
    let reviewTotal: Int?
}

private struct AxisTreeReviewSession {
    var state: AxisTreeReviewSessionState
}

enum InspectorPanelScope: Equatable {
    case project
    case instance
}

/// Where Project-inspector File naming should land after a footer jump.
enum InspectorFileNamingFocus: Equatable {
    case section
    case postScriptPrefix
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var openProjects: [OpenProject] = []
    @Published var activeProjectID: String?
    @Published var selectedInstanceKey: String?
    @Published var selectedInstanceKeys: Set<String> = []
    @Published var selectedAxisStopID: String?
    /// Axis tag to expand when inspector navigates to a stop.
    @Published var inspectorFocusedAxisTag: String?
    /// Bumps when the axis tree should expand and scroll to a stop (inspector / warnings).
    @Published var axisTreeFocusRequest: AxisTreeFocusRequest?
    @Published var conflictResolverRequest: AxisConflictResolverSession?
    @Published var planIssueResolverRequest: PlanIssueResolverSession?
    private var reviewSession: AxisTreeReviewSession?
    @Published private(set) var saveReviewSessionsByKey: [String: CommitPreflightSession] = [:]
    @Published var presentCommitDiffSheet = false
    @Published var showShortcutsHelp = false
    @Published private(set) var saveReviewOpenRequest: SaveReviewOpenRequest?
    @Published private(set) var saveReviewLoadingKeys: Set<String> = []
    @Published private(set) var saveReviewSelectedFontIDByProjectID: [String: String] = [:]
    @Published private(set) var saveReviewExplicitlyOpenedProjectIDs: Set<String> = []
    @Published var saveReviewUIStateByProjectID: [String: SaveReviewUIState] = [:]
    @Published var searchText = ""
    @Published private(set) var instanceSearchFocusToken: UUID?
    @Published var instanceFilter: InstanceFilter = .all
    @Published var instancePlan: InstancePlan?
    @Published private(set) var planRevision = 0
    @Published var statusMessage: String?
    @Published var isBusy = false
    @Published private(set) var instanceListDisplay = InstanceListDisplay.empty
    @Published private(set) var canSave = false
    @Published var inspectorPanelScope: InspectorPanelScope = .project
    /// Bumped when chrome should reveal the inspector column (e.g. footer clarifier tap).
    @Published private(set) var inspectorRevealToken = 0
    /// Optional File naming focus target paired with `inspectorRevealToken`.
    @Published private(set) var inspectorFileNamingFocus: InspectorFileNamingFocus?

    /// Confirmation for removing a dirty font file.
    @Published var confirmRemoveFont: FontRemovalRequest?
    /// Confirmation before moving a dirty font to another project.
    @Published var confirmMoveFont: FontMoveRequest?
    /// Confirmation before combining projects that contain dirty files.
    @Published var confirmCombineProjects: ProjectCombineRequest?
    /// Confirmation before splitting a font into a new project.
    @Published var confirmSplitFont: FontSplitRequest?
    /// Project workspace tab id pending close confirmation.
    @Published var confirmCloseProjectID: String?
    /// When true, app quit was requested while projects have unsaved state.
    @Published var confirmQuitRequested = false
    @Published var missingFontsRequest: MissingFontsRequest?
    @Published var confirmSaveToOriginal: CommitPreflightSession?
    @Published var confirmSetAsMasterFontID: String?
    @Published var confirmPushAxisTree = false
    @Published var persistentSaveError: String?
    @Published var pendingAddFontProjectID: String?
    /// Pick another open project as move/combine target.
    @Published var projectTargetPickerMode: ProjectTargetPickerMode?

    let workspaceDrag = WorkspaceDragCoordinator()

    private var debouncedPlanTask: Task<Void, Never>?
    private var statusMessageDismissTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let commitService = CommitService()
    private var sourceBookmarks: [String: Data] = [:]

    private static let statusMessageDisplayDuration: TimeInterval = 4

    var hasOpenProjects: Bool { !openProjects.isEmpty }

    var canSaveProject: Bool {
        guard let projectID = activeProjectID,
              openProjects.contains(where: { $0.id == projectID }) else { return false }
        guard let open = openProject(for: projectID) else { return false }
        return open.projectFileDirty || open.projectFileURL == nil
    }

    func projectFileDirty(for projectID: String) -> Bool {
        openProject(for: projectID)?.projectFileDirty ?? false
    }

    func projectNeedsProjectFileSave(projectID: String) -> Bool {
        guard let project = openProject(for: projectID) else { return false }
        return project.projectFileDirty || project.projectFileURL == nil
    }

    func projectHasDirtyFonts(projectID: String) -> Bool {
        openProject(for: projectID)?.document.fonts.contains(where: \.dirty) ?? false
    }

    func firstProjectNeedingProjectFileSave() -> String? {
        openProjects.first { projectNeedsProjectFileSave(projectID: $0.id) }?.id
    }

    var canSaveProjectOnQuit: Bool {
        firstProjectNeedingProjectFileSave() != nil
    }

    func quitConfirmationMessage() -> String {
        if firstProjectNeedingProjectFileSave() != nil {
            return "One or more projects have unsaved changes. Save the project file before quitting, or discard those changes."
        }
        return "Quit VarFont Studio?"
    }

    var canDragProjectForCombine: Bool { openProjects.count > 1 }

    var isWorkspaceDragActive: Bool { workspaceDrag.isActive }

    func canDragFont(forProjectID projectID: String) -> Bool {
        guard let project = openProjects.first(where: { $0.id == projectID }) else { return false }
        return openProjects.count > 1 || project.document.fonts.count > 1
    }

    func canSplitFont(fontID: String, fromProjectID projectID: String) -> Bool {
        guard let project = openProjects.first(where: { $0.id == projectID }),
              project.document.fonts.contains(where: { $0.id == fontID }) else { return false }
        return project.document.fonts.count > 1
    }

    var projectHasMultipleFiles: Bool {
        (project?.fonts.count ?? 0) >= 2
    }

    var saveReviewWindowTitle: String {
        guard let activeProjectID else { return "Review" }
        return saveReviewWindowTitle(forProjectID: activeProjectID)
    }

    func saveReviewWindowTitle(forProjectID projectID: String) -> String {
        if let open = openProject(for: projectID) {
            return "Review — \(projectTabLabel(for: open))"
        }
        return "Review"
    }

    func fontsForSaveReview(projectID: String) -> [FontDocument] {
        openProject(for: projectID)?.document.fonts ?? []
    }

    func saveReviewSelectedFontID(forProjectID projectID: String) -> String? {
        if let selected = saveReviewSelectedFontIDByProjectID[projectID] {
            return selected
        }
        return openProject(for: projectID)?.selectedFontID
    }

    func saveReviewSession(forProjectID projectID: String, fontID: String? = nil) -> CommitPreflightSession? {
        guard let fontID = fontID ?? saveReviewSelectedFontID(forProjectID: projectID) else { return nil }
        return saveReviewSessionsByKey[saveReviewSessionKey(projectID: projectID, fontID: fontID)]
    }

    func saveReviewUIState(forProjectID projectID: String) -> SaveReviewUIState {
        saveReviewUIStateByProjectID[projectID] ?? SaveReviewUIState()
    }

    func updateSaveReviewUIState(forProjectID projectID: String, _ transform: (inout SaveReviewUIState) -> Void) {
        var state = saveReviewUIState(forProjectID: projectID)
        transform(&state)
        saveReviewUIStateByProjectID[projectID] = state
    }

    func isSaveReviewLoading(forProjectID projectID: String, fontID: String? = nil) -> Bool {
        if let fontID {
            return saveReviewLoadingKeys.contains(saveReviewSessionKey(projectID: projectID, fontID: fontID))
        }
        return saveReviewLoadingKeys.contains { $0.hasPrefix("\(projectID)|") }
    }

    func selectSaveReviewFont(projectID: String, fontID: String) {
        let previousFontID = saveReviewSelectedFontIDByProjectID[projectID]
        saveReviewSelectedFontIDByProjectID[projectID] = fontID
        if previousFontID != fontID {
            updateSaveReviewUIState(forProjectID: projectID) { $0.searchQuery = "" }
        }
        guard canPreviewSaveReview(forProjectID: projectID, fontID: fontID) else { return }
        let isDirty = openProjects
            .first(where: { $0.id == projectID })?
            .document.fonts.first(where: { $0.id == fontID })?
            .dirty ?? false
        if saveReviewSession(forProjectID: projectID, fontID: fontID) == nil || isDirty {
            refreshCommitDiffPreview(forProjectID: projectID, fontID: fontID)
        }
    }

    func saveReviewWasExplicitlyOpened(forProjectID projectID: String) -> Bool {
        saveReviewExplicitlyOpenedProjectIDs.contains(projectID)
    }

    func presentSaveReviewWindow(forProjectID projectID: String? = nil) {
        let targetID = projectID ?? activeProjectID
        guard let targetID else {
            postStatusMessage("Open a project first.")
            return
        }
        guard canPreviewSaveReview(forProjectID: targetID) else {
            postStatusMessage("Nothing to preview — select a font in this project first.")
            return
        }
        if saveReviewSelectedFontIDByProjectID[targetID] == nil,
           let fontID = selectedFont(forProjectID: targetID)?.id {
            saveReviewSelectedFontIDByProjectID[targetID] = fontID
        }
        let fontID = saveReviewSelectedFontID(forProjectID: targetID)
        refreshCommitDiffPreview(forProjectID: targetID, fontID: fontID, presentSheet: false)
        saveReviewExplicitlyOpenedProjectIDs.insert(targetID)
        resetSaveReviewUIState(forProjectID: targetID)
        saveReviewOpenRequest = SaveReviewOpenRequest(projectID: targetID, token: UUID())
        Task {
            await commitService.ensureWorkerReady()
        }
    }

    func toggleSaveReviewWindow(forProjectID projectID: String? = nil) {
        let targetID = projectID ?? activeProjectID
        guard let targetID else {
            postStatusMessage("Open a project first.")
            return
        }
        if isSaveReviewWindowOpen(forProjectID: targetID) {
            closeSaveReviewWindow(forProjectID: targetID)
            return
        }
        presentSaveReviewWindow(forProjectID: targetID)
    }

    func presentShortcutsHelp() {
        showShortcutsHelp = true
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

    private func resetSaveReviewUIState(forProjectID projectID: String) {
        saveReviewUIStateByProjectID[projectID] = SaveReviewUIState()
    }

    /// Drop save-review payload when quitting or closing a restored auxiliary window.
    func clearSaveReviewState(forProjectID projectID: String? = nil, fontID: String? = nil) {
        if let projectID, let fontID {
            let key = saveReviewSessionKey(projectID: projectID, fontID: fontID)
            saveReviewSessionsByKey.removeValue(forKey: key)
            saveReviewLoadingKeys.remove(key)
        } else if let projectID {
            for key in saveReviewSessionsByKey.keys where key.hasPrefix("\(projectID)|") {
                saveReviewSessionsByKey.removeValue(forKey: key)
            }
            for key in saveReviewLoadingKeys where key.hasPrefix("\(projectID)|") {
                saveReviewLoadingKeys.remove(key)
            }
            saveReviewSelectedFontIDByProjectID.removeValue(forKey: projectID)
            saveReviewExplicitlyOpenedProjectIDs.remove(projectID)
            saveReviewUIStateByProjectID.removeValue(forKey: projectID)
        } else {
            saveReviewSessionsByKey.removeAll()
            saveReviewLoadingKeys.removeAll()
            saveReviewSelectedFontIDByProjectID.removeAll()
            saveReviewExplicitlyOpenedProjectIDs.removeAll()
            saveReviewUIStateByProjectID.removeAll()
        }
        presentCommitDiffSheet = false
    }

    private func saveReviewSessionKey(projectID: String, fontID: String) -> String {
        "\(projectID)|\(fontID)"
    }

    func openProject(for id: String) -> OpenProject? {
        openProjects.first { $0.id == id }
    }

    func font(forProjectID projectID: String, fontID: String) -> FontDocument? {
        openProject(for: projectID)?.document.fonts.first { $0.id == fontID }
    }

    func selectedFont(forProjectID projectID: String) -> FontDocument? {
        guard let open = openProject(for: projectID),
              let fontID = open.selectedFontID else { return nil }
        return open.document.fonts.first { $0.id == fontID }
    }

    func instancePlan(forProjectID projectID: String, fontID: String? = nil) -> InstancePlan? {
        guard let open = openProject(for: projectID) else { return nil }
        let resolvedFontID = fontID ?? open.selectedFontID
        guard let resolvedFontID else { return nil }
        if projectID == activeProjectID, resolvedFontID == selectedFontID, let instancePlan {
            return instancePlan
        }
        return InstancePlanner.plan(project: open.document, fontID: resolvedFontID)
    }

    func canPreviewSaveReview(forProjectID projectID: String, fontID: String) -> Bool {
        guard let open = openProject(for: projectID),
              open.document.fonts.contains(where: { $0.id == fontID }) else { return false }
        return instancePlan(forProjectID: projectID, fontID: fontID) != nil
    }

    func canPreviewSaveReview(forProjectID projectID: String) -> Bool {
        guard let open = openProject(for: projectID) else { return false }
        return open.document.fonts.contains { canPreviewSaveReview(forProjectID: projectID, fontID: $0.id) }
    }

    var canPreviewSaveReview: Bool {
        guard let activeProjectID else { return false }
        return canPreviewSaveReview(forProjectID: activeProjectID)
    }

    private func markProjectFileDirty(projectID: String? = nil) {
        guard let id = projectID ?? activeProjectID,
              let idx = openProjects.firstIndex(where: { $0.id == id }) else { return }
        guard !openProjects[idx].projectFileDirty else { return }
        openProjects[idx].projectFileDirty = true
        publishOpenProjects()
    }

    private func applyDefaultNameIDStrategy(to document: inout ProjectDocument) {
        document.nameidStrategy = StudioAppPreferences.defaultNameIDStrategy
        document.syncNameIDStrategyToFonts()
    }

    private func registerSourceBookmark(url: URL, fontID: String) {
        if let bookmark = SourceFontAccess.makeBookmark(for: url) {
            sourceBookmarks[fontID] = bookmark
        }
    }

    private func analyzeSourceFont(
        fontID: String? = nil,
        sourcePath: String
    ) throws -> FontAnalysis {
        let bookmark = fontID.flatMap { sourceBookmarks[$0] }
        return try SourceFontAccess.withReadableSourceURL(
            bookmark: bookmark,
            fallbackPath: sourcePath
        ) { sourceURL in
            try FontAnalysisReader.analyze(url: sourceURL)
        }
    }

    private func removeSourceBookmark(fontID: String) {
        sourceBookmarks.removeValue(forKey: fontID)
    }

    var project: ProjectDocument? {
        get { activeOpenProject?.document }
        set {
            guard let newValue, let idx = activeProjectIndex else { return }
            openProjects[idx].document = newValue
            publishOpenProjects()
        }
    }

    var selectedFontID: String? {
        get { activeOpenProject?.selectedFontID }
        set {
            guard let idx = activeProjectIndex else { return }
            openProjects[idx].selectedFontID = newValue
            publishOpenProjects()
        }
    }

    private var activeProjectIndex: Int? {
        guard let activeProjectID else { return nil }
        return openProjects.firstIndex { $0.id == activeProjectID }
    }

    private var activeOpenProject: OpenProject? {
        guard let idx = activeProjectIndex else { return nil }
        return openProjects[idx]
    }

    private func publishOpenProjects() {
        Task { @MainActor in
            openProjects = openProjects
        }
    }

    func postStatusMessage(_ message: String, dismissAfter seconds: TimeInterval? = nil) {
        let dismissAfter = seconds ?? Self.statusMessageDisplayDuration
        statusMessageDismissTask?.cancel()
        statusMessage = message
        statusMessageDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dismissAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func canBeginWorkspaceDrag(item: WorkspaceDragItem) -> Bool {
        guard !isBusy else { return false }
        switch item {
        case let .font(_, fromProjectID, _):
            return canDragFont(forProjectID: fromProjectID)
        case let .project(projectID, _):
            return canDragProjectForCombine && openProjects.contains(where: { $0.id == projectID })
        }
    }

    private func canSplitFontForDrag(item: WorkspaceDragItem) -> Bool {
        guard case let .font(fontID, fromProjectID, _) = item else { return false }
        return canSplitFont(fontID: fontID, fromProjectID: fromProjectID)
    }

    func beginWorkspaceDrag(item: WorkspaceDragItem, location: CGPoint) {
        guard canBeginWorkspaceDrag(item: item) else { return }
        workspaceDrag.begin(
            item: item,
            location: location,
            canSplitFont: canSplitFontForDrag(item: item)
        )
    }

    func updateWorkspaceDrag(location: CGPoint) {
        guard workspaceDrag.item != nil else { return }
        workspaceDrag.update(location: location)
    }

    func endWorkspaceDrag() {
        guard let (item, target) = workspaceDrag.end() else { return }

        guard let target else { return }

        switch (item, target) {
        case let (.font(fontID, fromProjectID, _), .reorderFont(projectID, beforeFontID)):
            guard fromProjectID == projectID else { return }
            reorderFont(draggedID: fontID, before: beforeFontID, projectID: projectID)
        case let (.font(fontID, fromProjectID, _), .reorderFontEnd(projectID)):
            guard fromProjectID == projectID else { return }
            moveFontToEnd(draggedID: fontID, projectID: projectID)
        case let (.font(fontID, fromProjectID, _), .project(targetID)):
            requestMoveFont(fontID: fontID, fromProjectID: fromProjectID, toProjectID: targetID)
        case let (.font(fontID, fromProjectID, _), .newProject):
            requestSplitFontToNewProject(fontID: fontID, fromProjectID: fromProjectID)
        case let (.project(sourceID, _), .project(targetID)):
            requestCombineProjects(sourceID: sourceID, intoTargetID: targetID)
        case (.project, .newProject),
             (.project, .reorderFont),
             (.project, .reorderFontEnd):
            break
        }
    }

    func cancelWorkspaceDrag() {
        workspaceDrag.cancel()
    }

    private var undoStack: [ProjectDocument] {
        get { activeOpenProject?.undoStack ?? [] }
        set {
            guard let idx = activeProjectIndex else { return }
            openProjects[idx].undoStack = newValue
            publishOpenProjects()
        }
    }

    private var redoStack: [ProjectDocument] {
        get { activeOpenProject?.redoStack ?? [] }
        set {
            guard let idx = activeProjectIndex else { return }
            openProjects[idx].redoStack = newValue
            publishOpenProjects()
        }
    }

    init() {
        Publishers.CombineLatest4(
            $instancePlan,
            $selectedAxisStopID,
            $instanceFilter,
            $searchText
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            self?.refreshInstanceListDisplay()
        }
        .store(in: &cancellables)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var selectedFont: FontDocument? {
        guard let project, let selectedFontID else { return nil }
        return project.fonts.first { $0.id == selectedFontID }
    }

    var filteredInstances: [PlannedInstance] {
        instanceListDisplay.groups.flatMap(\.instances)
    }

    var hasDuplicateInstances: Bool {
        instancePlan?.instances.contains(where: \.duplicate) ?? false
    }

    var visibleInstanceFilters: [InstanceFilter] {
        var filters: [InstanceFilter] = [.all, .included, .excluded]
        if hasDuplicateInstances {
            filters.append(.duplicates)
        }
        return filters
    }

    /// Keys currently highlighted in the instance list (multi- or single-select).
    var activeInstanceSelection: Set<String> {
        if !selectedInstanceKeys.isEmpty { return selectedInstanceKeys }
        if let selectedInstanceKey { return [selectedInstanceKey] }
        return []
    }

    func selectInstance(key: String, extend: Bool) {
        if extend {
            if selectedInstanceKeys.isEmpty, let selectedInstanceKey {
                selectedInstanceKeys = [selectedInstanceKey]
            }
            if selectedInstanceKeys.contains(key) {
                selectedInstanceKeys.remove(key)
            } else {
                selectedInstanceKeys.insert(key)
            }
            selectedInstanceKey = selectedInstanceKeys.contains(key) ? key : selectedInstanceKeys.sorted().first
        } else {
            let isOnlySelection = selectedInstanceKey == key
                && (selectedInstanceKeys.isEmpty || selectedInstanceKeys == [key])
            if isOnlySelection {
                selectedInstanceKey = nil
                selectedInstanceKeys = []
                return
            }
            selectedInstanceKeys = [key]
            selectedInstanceKey = key
        }
    }

    func setInstancesIncluded(keys: Set<String>, included: Bool) {
        guard !keys.isEmpty else { return }
        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }

        pushUndoSnapshot()
        var font = project.fonts[fontIndex]
        if included {
            font.excludedInstanceKeys.removeAll { keys.contains($0) }
        } else {
            for key in keys where !font.excludedInstanceKeys.contains(key) {
                font.excludedInstanceKeys.append(key)
            }
        }
        font.dirty = true
        project.fonts[fontIndex] = font
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    var allVisibleInstancesIncluded: Bool {
        let visible = filteredInstances
        guard !visible.isEmpty else { return false }
        return visible.allSatisfy(\.included)
    }

    var hasMixedVisibleInclusion: Bool {
        let visible = filteredInstances
        guard !visible.isEmpty else { return false }
        let includedCount = visible.filter(\.included).count
        return includedCount > 0 && includedCount < visible.count
    }

    func setAllVisibleInstancesIncluded(_ included: Bool) {
        setFilteredInstancesIncluded(included)
    }

    func toggleAllVisibleInstancesIncluded() {
        setAllVisibleInstancesIncluded(!allVisibleInstancesIncluded)
    }

    // MARK: - Naming order chain

    var namingChainTags: [String] {
        guard let project, let font = selectedFont else { return [] }
        return Self.mergedNamingOrder(projectOrder: project.naming.order, axisTags: font.axes.map(\.tag))
    }

    var inferredNamingChainOrder: [String] {
        guard let project, let font = selectedFont else { return [] }
        let baseline = project.naming.inferredOrder ?? project.naming.order
        return Self.mergedNamingOrder(projectOrder: baseline, axisTags: font.axes.map(\.tag))
    }

    var namingChainIsReordered: Bool {
        !inferredNamingChainOrder.isEmpty && namingChainTags != inferredNamingChainOrder
    }

    /// True when naming order or axis instance-grid roles differ from import-time inference.
    var namingDefaultsNeedRestore: Bool {
        guard let font = selectedFont else { return false }
        if namingChainIsReordered { return true }
        return font.axes.contains { axis in
            guard let inferred = axis.roleInferred else { return false }
            return axis.role != inferred
        }
    }

    var namingChainSummary: String {
        namingChainTags.joined(separator: " → ")
    }

    /// Full naming order filtered to naming-visible axes plus clarifier tokens.
    var namingChainInstanceTags: [String] {
        namingChainTags.filter { tag in
            if NamingToken.isPostscriptHyphen(tag) { return true }
            if NamingToken.isClarifier(tag) { return true }
            guard let axis = selectedFont?.axes.first(where: { $0.tag == tag }) else { return false }
            return axis.role == .instance || axis.isDesignRecordOnly
        }
    }

    /// Tags shown in the chain footer; pinned axes, empty clarifiers, and registration-covered
    /// clarifiers are omitted so the chain matches composed instance names.
    func visibleNamingChainTags(hideStatOnly: Bool) -> [String] {
        let base = hideStatOnly ? namingChainInstanceTags : namingChainTags
        guard let fontID = selectedFontID else { return base }
        return base.filter { tag in
            if NamingToken.isClarifier(tag) {
                return clarifierAppearsInNamingChain(for: tag, fontID: fontID)
            }
            return true
        }
    }

    func clarifierHasValue(for token: String, fontID: String) -> Bool {
        guard let category = NamingToken.clarifierCategory(for: token) else { return false }
        return fileRole(for: fontID)?.label(for: category) != nil
    }

    /// Clarifier tokens that still contribute a segment (have a label and are not covered by registration).
    func clarifierAppearsInNamingChain(for token: String, fontID: String) -> Bool {
        guard let category = NamingToken.clarifierCategory(for: token) else { return false }
        if clarifierCoveredByRegistration(category: category, for: fontID) { return false }
        return clarifierHasValue(for: token, fontID: fontID)
    }

    func namingChainSummary(hideStatOnly: Bool) -> String {
        visibleNamingChainTags(hideStatOnly: hideStatOnly).joined(separator: " → ")
    }

    /// Maps a visible-order insertion index to a full-order `insertBeforeIndex` for `moveTag`.
    /// `visibleInsertBefore` ranges over `0...visibleTags.count`.
    func namingChainInsertIndex(
        moving draggedTag: String,
        visibleInsertBefore: Int,
        hideStatOnly: Bool
    ) -> Int {
        let fullTags = namingChainTags
        guard hideStatOnly else {
            return min(max(0, visibleInsertBefore), fullTags.count)
        }

        let visibleTags = visibleNamingChainTags(hideStatOnly: true)
        if visibleInsertBefore >= visibleTags.count {
            // Append after the last visible axis: land just past it in the full order.
            if let lastVisible = visibleTags.last,
               let fullIndex = fullTags.firstIndex(of: lastVisible) {
                return fullIndex + 1
            }
            return fullTags.count
        }

        let anchorTag = visibleTags[visibleInsertBefore]
        return fullTags.firstIndex(of: anchorTag) ?? fullTags.count
    }

    var namingChainPreviewName: String {
        if let name = selectedInstance?.composedName, !name.isEmpty {
            return name
        }
        if let name = instancePlan?.instances.first?.composedName, !name.isEmpty {
            return name
        }
        return effectiveElidedFallbackDisplay.value
    }

    /// True when the naming preview is the collapsed elided fallback (not a partial compose).
    var namingChainPreviewIsElidedFallback: Bool {
        if let instance = selectedInstance ?? instancePlan?.instances.first {
            return !instance.namingChain.isEmpty && instance.namingChain.allSatisfy(\.elided)
        }
        return true
    }

    var namingChainPreviewPostScript: String {
        guard let project, let font = selectedFont else { return "" }
        let prefix = font.options.familyPSPrefix?.trimmingCharacters(in: .whitespacesAndNewlines)
        let familyPrefix = (prefix?.isEmpty == false) ? prefix! : "Family"
        let coords = selectedInstance?.coords
            ?? instancePlan?.instances.first?.coords
            ?? [:]
        return PostScriptNaming.composeInstanceName(
            familyPrefix: familyPrefix,
            coords: coords,
            axes: font.axes,
            naming: project.naming,
            fileRole: font.fileRole,
            fileStatRegistration: font.fileStatRegistration
        )
    }

    var effectiveElidedFallbackDisplay: (value: String, inferred: Bool) {
        guard let project, let font = selectedFont else {
            return (project?.naming.elidedFallback ?? "Regular", false)
        }
        let result = ElidedFallbackResolver.resolve(
            axes: font.axes,
            namingOrder: project.naming.order,
            fileStatRegistration: font.fileStatRegistration,
            sourceElidedFallback: project.naming.elidedFallback,
            fileRole: font.fileRole
        )
        return (result.value, result.inferred)
    }

    func axisDisplayName(for tag: String) -> String {
        if let clarifier = NamingToken.clarifierDisplayName[tag] {
            return clarifier
        }
        if let name = selectedFont?.axes.first(where: { $0.tag == tag })?.displayName, !name.isEmpty {
            return name
        }
        return tag
    }

    func isClarifierNamingToken(_ tag: String) -> Bool {
        NamingToken.isClarifier(tag)
    }

    func isPostscriptHyphenToken(_ tag: String) -> Bool {
        NamingToken.isPostscriptHyphen(tag)
    }

    func setNamingOrder(_ tags: [String]) {
        guard var project, let font = selectedFont else { return }
        let axisTags = font.axes.map(\.tag)
        let normalized = Self.mergedNamingOrder(projectOrder: tags, axisTags: axisTags)
        guard normalized != project.naming.order else { return }

        pushUndoSnapshot()
        project.naming.order = normalized
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func restoreNamingDefaults() {
        guard var project,
              let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }),
              namingDefaultsNeedRestore else { return }

        pushUndoSnapshot()

        let font = project.fonts[fontIndex]
        project.naming.order = Self.mergedNamingOrder(
            projectOrder: project.naming.inferredOrder ?? project.naming.order,
            axisTags: font.axes.map(\.tag)
        )
        project.naming.order = NamingPolicy.resetPostscriptHyphenToDefault(in: project.naming.order)

        for index in project.fonts[fontIndex].axes.indices {
            if let inferred = project.fonts[fontIndex].axes[index].roleInferred {
                project.fonts[fontIndex].axes[index].role = inferred
            }
        }

        project.fonts[fontIndex].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    /// Moves `draggedTag` so it sits immediately before the item that occupied
    /// `insertBeforeIndex` in the original array (slot semantics in the chain footer).
    static func moveTag(_ tags: [String], moving draggedTag: String, toIndex insertBeforeIndex: Int) -> [String] {
        guard let fromIndex = tags.firstIndex(of: draggedTag) else { return tags }

        var reordered = tags
        reordered.remove(at: fromIndex)

        var insertIndex = insertBeforeIndex
        if fromIndex < insertBeforeIndex {
            insertIndex -= 1
        }
        insertIndex = min(max(0, insertIndex), reordered.count)
        reordered.insert(draggedTag, at: insertIndex)
        return reordered
    }

    /// Inserts `draggedTag` immediately before `anchorTag` (legacy helper).
    static func reorderTags(_ tags: [String], moving draggedTag: String, before anchorTag: String) -> [String] {
        guard let anchorIndex = tags.firstIndex(of: anchorTag) else { return tags }
        return moveTag(tags, moving: draggedTag, toIndex: anchorIndex)
    }

    func reorderNamingChain(moving draggedTag: String, toIndex targetIndex: Int) {
        setNamingOrder(Self.moveTag(namingChainTags, moving: draggedTag, toIndex: targetIndex))
    }

    func reorderNamingChain(moving draggedTag: String, before anchorTag: String) {
        guard let anchorIndex = namingChainTags.firstIndex(of: anchorTag) else { return }
        reorderNamingChain(moving: draggedTag, toIndex: anchorIndex)
    }

    static func mergedNamingOrder(projectOrder: [String], axisTags: [String]) -> [String] {
        NamingPolicy.mergedOrder(projectOrder: projectOrder, axisTags: axisTags)
    }

    private func refreshInstanceListDisplay() {
        guard let instancePlan else {
            instanceListDisplay = .empty
            return
        }

        if instanceFilter == .duplicates, !instancePlan.instances.contains(where: \.duplicate) {
            instanceFilter = .all
        }

        var captions: [String: String] = [:]
        var includedByKey: [String: Bool] = [:]
        captions.reserveCapacity(instancePlan.instances.count)
        includedByKey.reserveCapacity(instancePlan.instances.count)
        for instance in instancePlan.instances {
            let pairs = coordCaptionPairs(for: instance)
            captions[instance.key] = StudioFormatting.truncatingCoordCaption(pairs: pairs)
            includedByKey[instance.key] = instance.included
        }

        let rows = computeFilteredInstances(from: instancePlan.instances, coordCaptions: captions)
        let shouldGroup = instancePlan.instances.count > 24
        let groups = computeGroupedInstances(from: rows, shouldGroup: shouldGroup)

        instanceListDisplay = InstanceListDisplay(
            groups: groups,
            isEmpty: rows.isEmpty,
            summary: computeInstanceListSummary(
                filteredCount: rows.count,
                totalCount: instancePlan.instances.count,
                groups: groups,
                plan: instancePlan
            ),
            axisStopFilterLabel: selectedAxisStopFilterLabelValue,
            coordCaptions: captions,
            includedByKey: includedByKey
        )
    }

    private func computeFilteredInstances(
        from rows: [PlannedInstance],
        coordCaptions: [String: String]
    ) -> [PlannedInstance] {
        var filtered = rows

        switch instanceFilter {
        case .all:
            break
        case .included:
            filtered = filtered.filter(\.included)
        case .excluded:
            filtered = filtered.filter { !$0.included }
        case .duplicates:
            filtered = filtered.filter(\.duplicate)
        }

        if let stopFilter = selectedAxisStopFilter {
            filtered = filtered.filter { instance in
                guard let value = instance.coords[stopFilter.tag] else { return false }
                return AxisCoordinate.valuesEqual(value, stopFilter.value)
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            filtered = filtered.filter { instance in
                instance.composedName.localizedCaseInsensitiveContains(query)
                    || instance.key.localizedCaseInsensitiveContains(query)
                    || (coordCaptions[instance.key]?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return filtered
    }

    private func computeGroupedInstances(
        from rows: [PlannedInstance],
        shouldGroup: Bool
    ) -> [InstanceGroup] {
        guard !rows.isEmpty else { return [] }
        guard shouldGroup, let groupTag = instanceGroupByTag else {
            return [InstanceGroup(label: "", instances: rows)]
        }

        var order: [String] = []
        var buckets: [String: [PlannedInstance]] = [:]
        for instance in rows {
            let label = instanceGroupLabel(for: instance, axisTag: groupTag)
            if buckets[label] == nil {
                order.append(label)
            }
            buckets[label, default: []].append(instance)
        }
        return order.map { InstanceGroup(label: $0, instances: buckets[$0] ?? []) }
    }

    private func computeInstanceListSummary(
        filteredCount: Int,
        totalCount: Int,
        groups: [InstanceGroup],
        plan: InstancePlan
    ) -> String {
        let included = plan.formula.totalIncluded
        let generated = plan.formula.totalGenerated
        let hasNamedGroups = groups.count > 1 && groups.first?.label.isEmpty == false

        if hasNamedGroups {
            if filteredCount != totalCount {
                return "\(groups.count) groups · \(filteredCount) of \(totalCount) shown · \(included) of \(generated) included"
            }
            return "\(groups.count) groups · \(included) of \(generated) included"
        }

        if filteredCount != totalCount {
            return "\(filteredCount) of \(totalCount) shown · \(included) of \(generated) included"
        }
        return "\(included) of \(generated) included"
    }

    private var selectedAxisStopFilterLabelValue: String? {
        guard let filter = selectedAxisStopFilter else { return nil }
        if let name = filter.stopName {
            return "\(name) (\(filter.tag))"
        }
        return filter.tag
    }

    private var selectedAxisStopFilter: (tag: String, value: Double, stopName: String?)? {
        guard let stopID = selectedAxisStopID, let font = selectedFont else { return nil }
        for axis in font.axes {
            guard let stop = axis.values.first(where: { $0.id == stopID }) else { continue }
            return (axis.tag, stop.value, stop.name)
        }
        return nil
    }

    private var instanceGroupByTag: String? {
        guard let project, let font = selectedFont else { return nil }
        let gridTags = Set(font.axes.filter { $0.role == .instance }.map(\.tag))
        for tag in project.naming.order where gridTags.contains(tag) {
            return tag
        }
        return font.axes.first { $0.role == .instance }?.tag
    }

    private func instanceGroupLabel(for instance: PlannedInstance, axisTag: String) -> String {
        if let link = instance.namingChain.first(where: { $0.tag == axisTag }) {
            return link.name
        }
        if let value = instance.coords[axisTag],
           let axis = selectedFont?.axes.first(where: { $0.tag == axisTag }),
           let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) {
            return stop.name
        }
        if let value = instance.coords[axisTag] {
            return Self.formatCoordValue(value)
        }
        return "Other"
    }

    func instanceCoordsCaption(_ instance: PlannedInstance) -> String {
        coordCaptionPairs(for: instance).joined(separator: " ")
    }

    private func coordCaptionPairs(for instance: PlannedInstance) -> [String] {
        let order = project?.naming.order ?? instance.coords.keys.sorted()
        return StudioFormatting.coordPairs(coords: instance.coords, namingOrder: order)
    }

    func clearAxisStopFilter() {
        selectedAxisStopID = nil
    }

    func toggleAxisStopSelection(stopID: String) {
        if selectedAxisStopID == stopID {
            selectedAxisStopID = nil
        } else {
            selectedAxisStopID = stopID
        }
    }

    func setFilteredInstancesIncluded(_ included: Bool) {
        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }
        let keys = Set(filteredInstances.map(\.key))
        guard !keys.isEmpty else { return }

        pushUndoSnapshot()
        var font = project.fonts[fontIndex]
        if included {
            font.excludedInstanceKeys.removeAll { keys.contains($0) }
        } else {
            for key in keys where !font.excludedInstanceKeys.contains(key) {
                font.excludedInstanceKeys.append(key)
            }
        }
        font.dirty = true
        project.fonts[fontIndex] = font
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    private static func formatCoordValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    var selectedInstance: PlannedInstance? {
        guard let key = selectedInstanceKey, let instancePlan else { return nil }
        return instancePlan.instances.first { $0.key == key }
    }

    /// Inspector requires exactly one selected instance.
    var inspectorInspectableInstance: PlannedInstance? {
        guard activeInstanceSelection.count == 1 else { return nil }
        return selectedInstance
    }

    // MARK: - Inspector

    func isInstanceIncluded(_ key: String) -> Bool {
        instanceListDisplay.includedByKey[key]
            ?? instancePlan?.instances.first(where: { $0.key == key })?.included
            ?? true
    }

    func instanceAffectedByUnresolvedConflict(_ instance: PlannedInstance) -> Bool {
        primaryConflictAxis(for: instance) != nil
    }

    private func instanceParticipates(inStopID stopID: String, instance: PlannedInstance) -> Bool {
        guard let font = selectedFont else { return false }
        for axis in font.axes {
            guard let stop = axis.values.first(where: { $0.id == stopID }) else { continue }
            guard let coord = instance.coords[axis.tag] else { return false }
            return AxisCoordinate.valuesEqual(coord, stop.value)
        }
        return false
    }

    func primaryConflictAxis(for instance: PlannedInstance) -> AxisConflictBundle? {
        axisConflictBundles.first { bundle in
            bundle.involvedStopIDs.contains { instanceParticipates(inStopID: $0, instance: instance) }
        }
    }

    var axisConflictBundles: [AxisConflictBundle] {
        guard let instancePlan, let font = selectedFont, let project else { return [] }
        return AxisConflictBundler.bundles(
            warnings: instancePlan.warnings,
            axes: font.axes,
            namingOrder: project.naming.order
        ).map { bundle in
            var updated = bundle
            updated.symptomSummary = ConflictResolver.symptomSummary(
                for: bundle,
                font: font,
                naming: project.naming
            )
            return updated
        }
    }

    var unresolvedAxisConflictCount: Int { axisConflictBundles.count }

    func bundle(for axisTag: String) -> AxisConflictBundle? {
        axisConflictBundles.first { $0.axisTag == axisTag }
    }

    func presentConflictResolver(for axisTag: String) {
        guard let bundle = bundle(for: axisTag) else { return }
        presentConflictResolver(bundle: bundle)
    }

    func presentConflictResolver(bundle: AxisConflictBundle) {
        let position = reviewSessionPosition(for: .axisConflict(bundle))
        conflictResolverRequest = AxisConflictResolverSession(
            bundle: bundle,
            reviewPosition: position?.current,
            reviewTotal: position?.total
        )
        focusConflictAxis(bundle)
    }

    func presentFirstConflictResolver() {
        guard let first = axisConflictBundles.first else { return }
        presentConflictResolver(bundle: first)
    }

    func dismissConflictResolver() {
        conflictResolverRequest = nil
        reviewSession = nil
    }

    func reviewQueue() -> [AxisTreeReviewItem] {
        guard let instancePlan, selectedFont != nil, let project else { return [] }
        return AxisTreeReviewQueue.build(
            warnings: instancePlan.warnings,
            conflictBundles: axisConflictBundles,
            namingOrder: project.naming.order
        )
    }

    var reviewIssueCount: Int { reviewQueue().count }

    func informationalPlanWarnings() -> [PlanWarning] {
        guard let instancePlan, let project else { return [] }
        return AxisTreeReviewQueue.informationalWarnings(
            warnings: instancePlan.warnings,
            namingOrder: project.naming.order
        )
    }

    func startReviewSession(jumpingTo warning: PlanWarning? = nil) {
        let queue = reviewQueue()
        guard !queue.isEmpty else { return }
        let index: Int
        if let warning {
            let key = PlanIssueCodes.issueKey(for: warning)
            index = queue.firstIndex { item in
                guard case let .planIssue(w) = item else { return false }
                return PlanIssueCodes.issueKey(for: w) == key
            } ?? 0
        } else {
            index = 0
        }
        reviewSession = AxisTreeReviewSession(
            state: AxisTreeReviewSessionState(scope: .full, initialTotal: queue.count)
        )
        presentReviewItem(at: index, in: queue)
    }

    func startAxisReviewSession(on axisTag: String) {
        let queue = AxisTreeReviewQueue.filter(reviewQueue(), axisTag: axisTag)
        guard !queue.isEmpty else { return }
        reviewSession = AxisTreeReviewSession(
            state: AxisTreeReviewSessionState(scope: .axis(axisTag), initialTotal: queue.count)
        )
        presentReviewItem(at: 0, in: queue)
    }

    func continueReviewSession() {
        advanceReviewSession()
    }

    func advanceReviewSession() {
        guard var session = reviewSession else { return }
        session.state.completedCount += 1
        let queue = scopedReviewQueue()
        guard !queue.isEmpty else {
            planIssueResolverRequest = nil
            conflictResolverRequest = nil
            reviewSession = nil
            return
        }
        reviewSession = session
        presentReviewItem(at: 0, in: queue)
    }

    private func scopedReviewQueue() -> [AxisTreeReviewItem] {
        let full = reviewQueue()
        guard let session = reviewSession else { return full }
        return session.state.scopedQueue(from: full)
    }

    func endReviewSession() {
        reviewSession = nil
    }

    private func presentReviewItem(at index: Int, in queue: [AxisTreeReviewItem]) {
        guard index < queue.count else {
            planIssueResolverRequest = nil
            conflictResolverRequest = nil
            return
        }
        switch queue[index] {
        case let .planIssue(warning):
            conflictResolverRequest = nil
            presentPlanIssueResolver(for: warning)
        case let .axisConflict(bundle):
            planIssueResolverRequest = nil
            presentConflictResolver(bundle: bundle)
        }
    }

    private func reviewSessionPosition(for item: AxisTreeReviewItem) -> (current: Int, total: Int)? {
        guard let session = reviewSession else { return nil }
        _ = item
        return session.state.displayPosition()
    }

    func resolvablePlanWarnings(for axisTag: String) -> [PlanWarning] {
        guard selectedFont != nil else { return [] }
        return (instancePlan?.warnings ?? []).filter { warning in
            guard warning.axis == axisTag else { return false }
            return PlanIssueCodes.resolvable.contains(warning.code)
        }
    }

    func planIssueProposals(for warning: PlanWarning) -> [PlanIssueProposal] {
        guard let font = selectedFont else { return [] }
        return PlanIssueResolver.proposals(for: warning, font: font)
    }

    func applyPlanIssueFix(_ action: PlanIssueAction, andContinue: Bool = false) {
        if case .openAxisConflicts(let axisTag) = action {
            planIssueResolverRequest = nil
            if let tag = axisTag, let bundle = bundle(for: tag) {
                presentConflictResolver(bundle: bundle)
            } else if let first = axisConflictBundles.first {
                presentConflictResolver(bundle: first)
            }
            return
        }

        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }
        pushUndoSnapshot()
        PlanIssueResolver.apply(action, to: &project.fonts[fontIndex])
        project.fonts[fontIndex].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
        if andContinue {
            advanceReviewSession()
        } else {
            planIssueResolverRequest = nil
            reviewSession = nil
        }
    }

    func presentPlanIssueResolver(for warning: PlanWarning) {
        let item = AxisTreeReviewItem.planIssue(warning)
        let position = reviewSessionPosition(for: item)
        planIssueResolverRequest = PlanIssueResolverSession(
            warning: warning,
            reviewPosition: position?.current,
            reviewTotal: position?.total
        )
        if let axis = warning.axis {
            inspectorFocusedAxisTag = axis
            if let stopID = warning.stopIDs?.first {
                selectedAxisStopID = stopID
                axisTreeFocusRequest = AxisTreeFocusRequest(
                    axisTag: axis,
                    stopID: stopID,
                    token: UUID()
                )
            }
        }
    }

    func presentFirstResolvablePlanIssue(on axisTag: String) {
        startAxisReviewSession(on: axisTag)
    }

    func setElidedFallback(_ value: String) {
        guard var project else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Regular" : trimmed
        guard resolved != project.naming.elidedFallback else { return }
        pushUndoSnapshot()
        project.naming.elidedFallback = resolved
        project.modified = Date()
        self.project = project
        regeneratePlan()
    }

    func updateCompoundStatName(id: String, name: String) {
        mutateSelectedFont { font in
            guard let index = font.compoundStatValues.firstIndex(where: { $0.id == id }) else { return }
            font.compoundStatValues[index].name = name
        }
    }

    func updateCompoundStatElidable(id: String, elidable: Bool) {
        mutateSelectedFont { font in
            guard let index = font.compoundStatValues.firstIndex(where: { $0.id == id }) else { return }
            font.compoundStatValues[index].elidable = elidable
        }
    }

    func updateCompoundStatCoordinate(id: String, tag: String, value: Double) {
        mutateSelectedFont { font in
            guard let index = font.compoundStatValues.firstIndex(where: { $0.id == id }) else { return }
            font.compoundStatValues[index].coords[tag] = value
            CompoundStatCoordinateSync.syncIndicesAndValues(
                compound: &font.compoundStatValues[index],
                designAxisOrder: font.axes
            )
        }
    }

    func dismissPlanIssueResolver() {
        planIssueResolverRequest = nil
        reviewSession = nil
    }

    func applyConflictFix(_ action: ConflictFixAction, axisTag: String, andContinue: Bool = false) {
        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }
        pushUndoSnapshot()
        ConflictResolver.apply(action, axisTag: axisTag, to: &project.fonts[fontIndex])
        project.fonts[fontIndex].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
        if andContinue {
            advanceReviewSession()
        } else {
            conflictResolverRequest = nil
            if reviewSession != nil {
                reviewSession = nil
            } else if let sameAxis = axisConflictBundles.first(where: { $0.axisTag == axisTag }) {
                presentConflictResolver(bundle: sameAxis)
            } else if let next = axisConflictBundles.first {
                presentConflictResolver(bundle: next)
            }
        }
    }

    private func focusConflictAxis(_ bundle: AxisConflictBundle) {
        inspectorFocusedAxisTag = bundle.axisTag
        guard let stopID = bundle.involvedStopIDs.first else { return }
        selectedAxisStopID = stopID
        axisTreeFocusRequest = AxisTreeFocusRequest(
            axisTag: bundle.axisTag,
            stopID: stopID,
            token: UUID()
        )
    }

    func axisStop(for instance: PlannedInstance, tag: String) -> (axisTag: String, stopID: String)? {
        guard let font = selectedFont,
              let coord = instance.coords[tag],
              let axis = font.axes.first(where: { $0.tag == tag }),
              let stop = axis.values.first(where: { AxisCoordinate.valuesEqual($0.value, coord) }) else {
            return nil
        }
        return (tag, stop.id)
    }

    func focusInspectorAxisStop(tag: String, stopID: String) {
        inspectorFocusedAxisTag = tag
        selectedAxisStopID = stopID
    }

    func axisTag(forStopID stopID: String) -> String? {
        selectedFont?.axes.first { axis in
            axis.values.contains { $0.id == stopID }
        }?.tag
    }

    var conflictStopIDs: Set<String> {
        Set(axisConflictBundles.flatMap(\.involvedStopIDs))
    }

    func focusInspectorAxis(for instance: PlannedInstance, tag: String) {
        if let resolved = axisStop(for: instance, tag: tag) {
            focusInspectorAxisStop(tag: resolved.axisTag, stopID: resolved.stopID)
        }
    }

    func inspectorAxisCoordRows(for instance: PlannedInstance) -> [InspectorAxisCoordRow] {
        let order = project?.naming.order ?? instance.coords.keys.sorted()
        let extra = instance.coords.keys.filter { !order.contains($0) }.sorted()
        let tags = order.filter { instance.coords[$0] != nil } + extra

        return tags.compactMap { tag in
            guard let value = instance.coords[tag] else { return nil }
            let participatesInNaming = axisParticipatesInInstanceGrid(tag: tag)
            let link = instance.namingChain.first(where: { $0.tag == tag })
            let isElided = link?.elided ?? false
            let stop = axisStop(for: instance, tag: tag)
            let stopName: String
            if let link {
                stopName = link.name
            } else if let font = selectedFont,
                      let axis = font.axes.first(where: { $0.tag == tag }),
                      let match = axis.values.first(where: { AxisCoordinate.valuesEqual($0.value, value) }) {
                stopName = match.name
            } else {
                stopName = axisDisplayName(for: tag)
            }
            let showsElisionToggle = link != nil && stop != nil && participatesInNaming
            let isElidable: Bool
            if showsElisionToggle, let font = selectedFont,
               let axis = font.axes.first(where: { $0.tag == tag }),
               let match = axis.values.first(where: { $0.id == stop?.stopID }) {
                isElidable = match.elidable
            } else {
                isElidable = false
            }
            return InspectorAxisCoordRow(
                tag: tag,
                value: value,
                stopName: stopName,
                participatesInNaming: participatesInNaming,
                isElided: isElided,
                stopID: stop?.stopID,
                showsElisionToggle: showsElisionToggle,
                isElidable: isElidable
            )
        }
    }

    func openTypePreviewRows(for instance: PlannedInstance) -> [InspectorOpenTypeRow] {
        guard let font = selectedFont else { return [] }
        var rows: [InspectorOpenTypeRow] = []

        for link in instance.namingChain {
            let axisLabel = font.axes.first(where: { $0.tag == link.tag })?.displayName ?? link.tag
            let value = instance.coords[link.tag].map(StudioFormatting.axisValue) ?? "—"
            let elideNote = link.elided ? " · elidable" : ""
            rows.append(
                InspectorOpenTypeRow(
                    id: "stat-\(link.tag)",
                    table: "STAT",
                    field: "Instance coordinates",
                    content: "\(axisLabel) “\(link.name)” @ \(value)\(elideNote)",
                    sources: [.stat, .planned],
                    isDerived: true,
                    kind: .statAxisValue
                )
            )
        }

        let coordText = StudioFormatting.coordPairs(
            coords: instance.coords,
            namingOrder: project?.naming.order ?? []
        ).joined(separator: " ")

        rows.append(
            InspectorOpenTypeRow(
                id: "fvar-coords",
                table: "fvar",
                field: "coordinates",
                content: coordText,
                sources: [.fvar, .planned],
                isDerived: true,
                kind: .fvarCoordinates
            )
        )

        rows.append(
            InspectorOpenTypeRow(
                id: "fvar-subfamily",
                table: "fvar",
                field: "Subfamily name",
                content: "→ “\(instance.composedName)”",
                sources: [.fvar, .planned],
                isDerived: true,
                kind: .fvarSubfamilyNameID
            )
        )

        if let summary = instancePlan?.namePlanSummary {
            var parts: [String] = []
            if let prefix = summary.familyPSPrefix {
                parts.append("PS prefix: \(prefix)")
            }
            if let range = summary.newIDRange, range.count == 2 {
                parts.append("IDs \(range[0])–\(range[1])")
            }
            if let note = summary.note {
                parts.append(note)
            }
            if !parts.isEmpty {
                rows.append(
                    InspectorOpenTypeRow(
                        id: "name-summary",
                        table: "name",
                        field: "summary",
                        content: parts.joined(separator: " · "),
                        sources: [.name, .planned],
                        isDerived: true,
                        kind: .nameSummary
                    )
                )
            }
        }

        return rows
    }

    func showAllDuplicateInstances() {
        instanceFilter = .duplicates
        searchText = ""
    }

    func showDuplicateInstances(matchingName name: String) {
        instanceFilter = .duplicates
        searchText = name
    }

    func showDuplicateInstances(matching instance: PlannedInstance) {
        showDuplicateInstances(matchingName: instance.composedName)
    }

    func requestInstanceSearchFocus() {
        StudioFieldFocus.resignIfEditing()
        instanceSearchFocusToken = UUID()
    }

    func suggestedNewStopValue(for axis: AxisDefinition) -> Double {
        AxisStopSuggestions.suggestedValue(for: axis)
    }

    func conflictProposals(for bundle: AxisConflictBundle) -> [ConflictResolutionProposal] {
        guard let axis = selectedFont?.axes.first(where: { $0.tag == bundle.axisTag }) else { return [] }
        return ConflictResolver.proposals(for: bundle, axis: axis)
    }

    func conflictPreview(
        for bundle: AxisConflictBundle,
        applying action: ConflictFixAction
    ) -> ConflictFixPreview? {
        guard let font = selectedFont, let project else { return nil }
        return ConflictResolver.previewPlan(
            font: font,
            naming: project.naming,
            bundle: bundle,
            applying: action
        )
    }

    func currentConflictPreview(for bundle: AxisConflictBundle) -> ConflictFixPreview? {
        guard let font = selectedFont, let project else { return nil }
        let plan = InstancePlanner.plan(font: font, naming: project.naming)
        let bundles = AxisConflictBundler.bundles(
            warnings: plan.warnings,
            axes: font.axes,
            namingOrder: project.naming.order
        )
        let remaining = bundles.filter { $0.axisTag == bundle.axisTag }.count
        return ConflictFixPreview(
            totalInstances: plan.instances.count,
            duplicateInstanceCount: plan.instances.filter(\.duplicate).count,
            remainingAxisConflicts: remaining,
            sampleComposedNames: Array(plan.instances.prefix(3).map(\.composedName)),
            resolvesConflict: remaining == 0
        )
    }

    func presentAddFontPanel(projectID: String? = nil) {
        pendingAddFontProjectID = projectID ?? activeProjectID
        let panel = NSOpenPanel()
        panel.title = "Add Font to Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.fontContentTypes
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.addFont(at: url, toProjectID: self?.pendingAddFontProjectID ?? self?.activeProjectID)
                self?.pendingAddFontProjectID = nil
            }
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "New Project — Open Variable Font"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.fontContentTypes
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.createProject(from: url)
            }
        }
    }

    func presentOpenProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.varfontProject]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.openProjectFile(at: url)
            }
        }
    }

    func saveProject() {
        guard let projectID = activeProjectID,
              let open = openProject(for: projectID) else {
            postStatusMessage("No project selected.")
            return
        }
        if let url = open.projectFileURL {
            Task { @MainActor in
                await self.saveProject(document: open.document, to: url, projectID: projectID)
            }
        } else {
            presentSaveProjectAsPanel()
        }
    }

    func saveProjectAs() {
        presentSaveProjectAsPanel()
    }

    private func presentSaveProjectAsPanel() {
        guard let projectID = activeProjectID,
              let open = openProject(for: projectID) else {
            postStatusMessage("No project selected.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Project As"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.varfontProject]
        panel.nameFieldStringValue = defaultProjectFilename(for: open)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let normalized = Self.normalizedProjectFileURL(url)
            Task { @MainActor in
                await self?.saveProject(document: open.document, to: normalized, projectID: projectID)
            }
        }
    }

    private func defaultProjectFilename(for open: OpenProject) -> String {
        if let url = open.projectFileURL {
            return url.lastPathComponent
        }
        let base = projectTabLabel(for: open)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = base.isEmpty ? "Untitled" : base
        return ProjectFileFormat.defaultFilename(stem: sanitized.isEmpty ? "Untitled" : sanitized)
    }

    private static func normalizedProjectFileURL(_ url: URL) -> URL {
        ProjectFileFormat.normalizedProjectFileURL(url)
    }

    @MainActor
    private func saveProject(document: ProjectDocument, to url: URL, projectID: String) async {
        guard let idx = openProjects.firstIndex(where: { $0.id == projectID }) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try ProjectDocumentStore.save(openProjects[idx].document, to: url)
            openProjects[idx].projectFileURL = url
            openProjects[idx].projectFileDirty = false
            publishOpenProjects()
            postStatusMessage("Saved project — \(url.lastPathComponent)")
        } catch {
            postStatusMessage("Could not save project: \(error.localizedDescription)")
        }
    }

    func openProjectFile(at url: URL) async {
        let normalized = url.standardizedFileURL
        if let existing = openProjects.first(where: {
            $0.projectFileURL?.standardizedFileURL == normalized
        }) {
            activateProject(id: existing.id)
            postStatusMessage("Already open — \(normalized.lastPathComponent)")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let document = try ProjectDocumentStore.load(from: normalized)
            let missing = missingFontEntries(in: document)
            if missing.isEmpty {
                await finishOpeningProject(document: document, projectFileURL: normalized)
            } else {
                missingFontsRequest = MissingFontsRequest(
                    projectFileURL: normalized,
                    document: document,
                    entries: missing
                )
            }
        } catch {
            postStatusMessage("Could not open project: \(error.localizedDescription)")
        }
    }

    private func missingFontEntries(in document: ProjectDocument) -> [MissingFontEntry] {
        document.fonts.compactMap { font in
            let path = font.sourcePath
            guard !FileManager.default.fileExists(atPath: path) else { return nil }
            return MissingFontEntry(fontID: font.id, storedPath: path, resolvedURL: nil)
        }
    }

    func locateMissingFont(fontID: String) {
        guard var request = missingFontsRequest,
              let entryIndex = request.entries.firstIndex(where: { $0.fontID == fontID }) else { return }

        let panel = NSOpenPanel()
        panel.title = "Locate Font"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.fontContentTypes
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            request.entries[entryIndex].resolvedURL = url.standardizedFileURL
            self?.missingFontsRequest = request
        }
    }

    func cancelMissingFontsRequest() {
        missingFontsRequest = nil
    }

    func completeMissingFontsRequest() {
        guard let request = missingFontsRequest, request.allResolved else { return }
        var document = request.document
        for entry in request.entries {
            guard let resolvedURL = entry.resolvedURL,
                  let fontIndex = document.fonts.firstIndex(where: { $0.id == entry.fontID }) else { continue }
            document.fonts[fontIndex].sourcePath = resolvedURL.path
        }
        let projectURL = request.projectFileURL
        missingFontsRequest = nil
        Task { @MainActor in
            await self.finishOpeningProject(document: document, projectFileURL: projectURL)
        }
    }

    @MainActor
    private func finishOpeningProject(document: ProjectDocument, projectFileURL: URL) async {
        for font in document.fonts {
            let url = URL(fileURLWithPath: font.sourcePath)
            registerSourceBookmark(url: url, fontID: font.id)
        }

        let open = OpenProject(
            document: document,
            selectedFontID: document.preferredSelectedFontID,
            projectFileURL: projectFileURL,
            projectFileDirty: false
        )
        openProjects.append(open)
        activateProject(id: open.id)
        selectedInstanceKey = nil
        selectedInstanceKeys = []
        selectedAxisStopID = nil
        clearUndoHistory()
        regeneratePlan()
        canSave = document.fonts.contains(where: \.dirty)
        postStatusMessage("Opened project — \(projectFileURL.lastPathComponent)")
    }

    func handleApplicationTerminateRequest() -> Bool {
        guard firstProjectNeedingProjectFileSave() != nil else { return true }
        confirmQuitRequested = true
        return false
    }

    func completeApplicationTermination() {
        Task {
            await shutdownCommitWorker()
            await MainActor.run {
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
        }
    }

    func shutdownCommitWorker() async {
        await CommitService.shutdownWorker()
    }

    func confirmQuitDiscardAction() {
        confirmQuitRequested = false
        for project in openProjects {
            clearSaveReviewState(forProjectID: project.id)
            for font in project.document.fonts {
                removeSourceBookmark(fontID: font.id)
            }
        }
        openProjects.removeAll()
        activeProjectID = nil
        completeApplicationTermination()
    }

    func confirmQuitCancelAction() {
        confirmQuitRequested = false
        NSApplication.shared.reply(toApplicationShouldTerminate: false)
    }

    func confirmQuitSaveProjectAction() {
        guard let projectID = firstProjectNeedingProjectFileSave() else { return }
        saveProjectThenContinueQuit(projectID: projectID)
    }

    private func continueQuitAfterHandlingProjectSaves() {
        if firstProjectNeedingProjectFileSave() != nil {
            confirmQuitSaveProjectAction()
            return
        }
        confirmQuitRequested = false
        completeApplicationTermination()
    }

    private func saveProjectThenContinueQuit(projectID: String) {
        guard let open = openProject(for: projectID) else {
            continueQuitAfterHandlingProjectSaves()
            return
        }
        if let url = open.projectFileURL {
            Task { @MainActor in
                await self.saveProject(document: open.document, to: url, projectID: projectID)
                if self.openProject(for: projectID)?.projectFileDirty == false {
                    self.continueQuitAfterHandlingProjectSaves()
                }
            }
        } else {
            presentSaveProjectAsPanelForQuit(projectID: projectID)
        }
    }

    private func presentSaveProjectAsPanelForQuit(projectID: String) {
        guard let open = openProject(for: projectID) else { return }
        let panel = NSSavePanel()
        panel.title = "Save Project Before Quit"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.varfontProject]
        panel.nameFieldStringValue = defaultProjectFilename(for: open)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                self?.confirmQuitCancelAction()
                return
            }
            let normalized = Self.normalizedProjectFileURL(url)
            Task { @MainActor in
                await self?.saveProject(document: open.document, to: normalized, projectID: projectID)
                if self?.openProject(for: projectID)?.projectFileDirty == false {
                    self?.continueQuitAfterHandlingProjectSaves()
                }
            }
        }
    }

    /// Opens a new project tab with the font at `url`.
    func createProject(from url: URL) async {
        if let existing = findFont(normalizedPath: Self.normalizedPath(url)) {
            activateProject(id: existing.projectID)
            selectFont(id: existing.fontID)
            postStatusMessage("Already open — \(url.lastPathComponent)")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let analysis = try analyzeSourceFont(sourcePath: url.path)
            try validateVariableFont(analysis)
            var imported = ProjectImporter.newProject(from: analysis, sourceURL: url)
            applyDefaultNameIDStrategy(to: &imported)
            if let fontID = imported.fonts.first?.id {
                registerSourceBookmark(url: url, fontID: fontID)
            }
            let open = OpenProject(
                document: imported,
                selectedFontID: imported.preferredSelectedFontID,
                projectFileURL: nil,
                projectFileDirty: true
            )
            openProjects.append(open)
            activateProject(id: open.id)
            selectedInstanceKey = nil
            selectedInstanceKeys = []
            selectedAxisStopID = nil
            clearUndoHistory()
            regeneratePlan()
            postStatusMessage("Opened \(url.lastPathComponent)")
            canSave = false
        } catch let error as FontImportError {
            postStatusMessage(error.localizedDescription)
        } catch {
            postStatusMessage("Could not open font: \(error.localizedDescription)")
        }
    }

    func openFont(at url: URL) async {
        await createProject(from: url)
    }

    func addFont(at url: URL, toProjectID: String? = nil, selectAfterAdd: Bool = true) async {
        let targetID = toProjectID ?? activeProjectID
        if openProjects.isEmpty {
            await createProject(from: url)
            return
        }
        guard let targetID,
              openProjects.contains(where: { $0.id == targetID }) else {
            postStatusMessage("No project selected.")
            return
        }

        if let existing = findFont(normalizedPath: Self.normalizedPath(url)) {
            activateProject(id: existing.projectID)
            selectFont(id: existing.fontID)
            postStatusMessage("Already open — \(url.lastPathComponent)")
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let analysis = try analyzeSourceFont(sourcePath: url.path)
            try validateVariableFont(analysis)
            guard let idx = openProjects.firstIndex(where: { $0.id == targetID }) else { return }
            ProjectImporter.addFont(analysis, sourceURL: url, to: &openProjects[idx].document)
            let newFontID = openProjects[idx].document.fonts.last?.id
            if let newFontID {
                registerSourceBookmark(url: url, fontID: newFontID)
            }
            markProjectFileDirty(projectID: targetID)
            activateProject(id: targetID)
            if selectAfterAdd, let newFontID {
                selectFont(id: newFontID)
            }
            publishOpenProjects()
            regeneratePlan()
            postStatusMessage("Added \(url.lastPathComponent)")
        } catch let error as FontImportError {
            postStatusMessage(error.localizedDescription)
        } catch {
            postStatusMessage("Could not add font: \(error.localizedDescription)")
        }
    }

    func activateProject(id: String) {
        guard openProjects.contains(where: { $0.id == id }) else { return }
        activeProjectID = id
        selectedInstanceKey = nil
        selectedInstanceKeys = []
        selectedAxisStopID = nil
        refreshCanSave()
        regeneratePlan()
    }

    func selectFont(id: String) {
        selectedFontID = id
        selectedInstanceKey = nil
        selectedInstanceKeys = []
        regeneratePlan()
    }

    func selectMasterFont(for projectID: String? = nil) {
        let targetID = projectID ?? activeProjectID
        guard let targetID, let masterID = masterFontID(for: targetID) else { return }
        if targetID == activeProjectID {
            selectFont(id: masterID)
        } else if let idx = openProjects.firstIndex(where: { $0.id == targetID }) {
            openProjects[idx].selectedFontID = masterID
        }
    }

    func focusInspectorProjectScope(
        fontID: String? = nil,
        fileNaming: InspectorFileNamingFocus? = nil
    ) {
        if let fontID {
            selectFont(id: fontID)
        }
        inspectorPanelScope = .project
        inspectorFileNamingFocus = fileNaming
        inspectorRevealToken &+= 1
    }

    func clearInspectorFileNamingFocus() {
        inspectorFileNamingFocus = nil
    }

    func updateInspectorScopeForSelection() {
        if inspectorInspectableInstance != nil {
            inspectorPanelScope = .instance
        } else {
            inspectorPanelScope = .project
        }
    }

    func renameProject(id: String, displayName: String) {
        guard let idx = openProjects.firstIndex(where: { $0.id == id }) else { return }
        pushUndoSnapshot()
        syncProjectDisplayNameAndPrefix(
            normalizedProjectNaming(displayName),
            on: &openProjects[idx].document
        )
        openProjects[idx].document.modified = Date()
        publishOpenProjects()
        canSave = true
        regeneratePlan()
    }

    /// Inspector subtitle after file count — paired master PostScript prefix when set.
    func projectNamingSubtitle(for openProject: OpenProject) -> String {
        let prefix = masterFamilyPSPrefix(for: openProject.id)
        if !prefix.isEmpty { return prefix }
        if let name = openProject.document.displayName, !name.isEmpty { return name }
        return openProject.document.familyLabel
    }

    func masterFamilyPSPrefix(for projectID: String) -> String {
        guard let masterID = masterFontID(for: projectID),
              let font = font(forProjectID: projectID, fontID: masterID) else { return "" }
        return font.options.familyPSPrefix ?? ""
    }

    func projectTabLabel(for openProject: OpenProject) -> String {
        if let url = openProject.projectFileURL {
            return url.deletingPathExtension().lastPathComponent
        }
        if let name = openProject.document.displayName, !name.isEmpty {
            return name
        }
        if !openProject.document.familyLabel.isEmpty {
            return openProject.document.familyLabel
        }
        if let first = openProject.document.fonts.first {
            return fontBasename(for: first)
        }
        return "Project"
    }

    func fontBasename(for font: FontDocument) -> String {
        URL(fileURLWithPath: font.sourcePath).deletingPathExtension().lastPathComponent
    }

    func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    func instanceCountLabel(for font: FontDocument) -> String {
        guard activeProjectID != nil,
              let project,
              project.fonts.contains(where: { $0.id == font.id }) else { return "—" }
        if font.id == selectedFontID, let plan = instancePlan {
            return "\(plan.formula.totalGenerated)"
        }
        let estimate = font.axes.filter { $0.role == .instance }.map(\.values.count).reduce(1, *)
        return "~\(estimate)"
    }

    func isFontDirty(fontID: String) -> Bool {
        project?.fonts.first { $0.id == fontID }?.dirty ?? false
    }

    func clarifierSlotState(category: FileClarifierCategory, for fontID: String) -> ClarifierSlotState {
        guard let font = project?.fonts.first(where: { $0.id == fontID }) else {
            return .editable
        }
        let count = project?.fonts.count ?? 1
        return ClarifierSlotCoverage.slotState(category: category, font: font, projectFontCount: count)
    }

    func hasEditableClarifierSlots(for fontID: String) -> Bool {
        guard let font = project?.fonts.first(where: { $0.id == fontID }) else { return false }
        let count = project?.fonts.count ?? 1
        if ClarifierSlotCoverage.isMultiFileMaster(font: font, projectFontCount: count) {
            return false
        }
        if ClarifierSlotCoverage.hasEditableInferSlots(font: font, projectFontCount: count) {
            return true
        }
        // Allow Infer to fill an empty PostScript prefix even when clarifier slots are covered.
        let prefix = font.options.familyPSPrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return prefix.isEmpty
    }

    func requestRemoveFont(projectID: String, fontID: String) {
        guard openProjects.contains(where: { $0.id == projectID }),
              openProjects.first(where: { $0.id == projectID })?
                .document.fonts.contains(where: { $0.id == fontID }) == true else { return }
        confirmRemoveFont = FontRemovalRequest(projectID: projectID, fontID: fontID)
    }

    func confirmRemoveFontAction() {
        guard let request = confirmRemoveFont else { return }
        confirmRemoveFont = nil
        removeFont(id: request.fontID, fromProjectID: request.projectID)
    }

    func removeFont(id fontID: String, fromProjectID projectID: String) {
        guard let pIdx = openProjects.firstIndex(where: { $0.id == projectID }) else { return }
        let removedWasMaster = masterFontID(for: projectID) == fontID
        openProjects[pIdx].document.fonts.removeAll { $0.id == fontID }
        removeSourceBookmark(fontID: fontID)

        if openProjects[pIdx].document.fonts.isEmpty {
            closeProject(id: projectID, force: true)
            postStatusMessage("Project closed — no files remaining")
            return
        }

        if removedWasMaster {
            promoteFirstFontToMaster(projectIndex: pIdx)
        }

        if openProjects[pIdx].selectedFontID == fontID {
            openProjects[pIdx].selectedFontID = openProjects[pIdx].document.fonts.first?.id
        }

        activateProject(id: projectID)
        markProjectFileDirty(projectID: projectID)
        publishOpenProjects()
        refreshCanSave()
        regeneratePlan()
        postStatusMessage("Removed font from project")
    }

    func isMasterFont(fontID: String, projectID: String) -> Bool {
        masterFontID(for: projectID) == fontID
    }

    func reorderFont(draggedID: String, before anchorID: String, projectID: String) {
        guard draggedID != anchorID,
              let pIdx = openProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var fonts = openProjects[pIdx].document.fonts
        guard let fromIndex = fonts.firstIndex(where: { $0.id == draggedID }),
              let anchorIndex = fonts.firstIndex(where: { $0.id == anchorID }) else { return }
        let insertIndex = fromIndex < anchorIndex ? anchorIndex - 1 : anchorIndex
        guard fromIndex != insertIndex else { return }

        pushUndoSnapshot()
        let item = fonts.remove(at: fromIndex)
        fonts.insert(item, at: insertIndex)
        openProjects[pIdx].document.fonts = fonts
        openProjects[pIdx].document.modified = Date()
        promoteFirstFontToMaster(projectIndex: pIdx)
        publishOpenProjects()
        refreshCanSave()
        regeneratePlan()
    }

    func moveFontToEnd(draggedID: String, projectID: String) {
        guard let pIdx = openProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var fonts = openProjects[pIdx].document.fonts
        guard let fromIndex = fonts.firstIndex(where: { $0.id == draggedID }),
              fromIndex < fonts.count - 1 else { return }

        pushUndoSnapshot()
        let item = fonts.remove(at: fromIndex)
        fonts.append(item)
        openProjects[pIdx].document.fonts = fonts
        openProjects[pIdx].document.modified = Date()
        promoteFirstFontToMaster(projectIndex: pIdx)
        publishOpenProjects()
        refreshCanSave()
        regeneratePlan()
    }

    func presentMoveFontPicker(fontID: String, fromProjectID: String) {
        projectTargetPickerMode = .moveFont(fontID: fontID, fromProjectID: fromProjectID)
    }

    func presentCombineProjectsPicker(into targetProjectID: String) {
        projectTargetPickerMode = .combineInto(targetProjectID: targetProjectID)
    }

    func cancelProjectTargetPicker() {
        projectTargetPickerMode = nil
    }

    func completeProjectTargetPicker(selectedProjectID: String) {
        guard let mode = projectTargetPickerMode else { return }
        projectTargetPickerMode = nil
        switch mode {
        case let .moveFont(fontID, fromProjectID):
            requestMoveFont(fontID: fontID, fromProjectID: fromProjectID, toProjectID: selectedProjectID)
        case let .combineInto(targetProjectID):
            requestCombineProjects(sourceID: selectedProjectID, intoTargetID: targetProjectID)
        }
    }

    func requestMoveFont(fontID: String, fromProjectID: String, toProjectID: String) {
        guard fromProjectID != toProjectID,
              let fromIdx = openProjects.firstIndex(where: { $0.id == fromProjectID }),
              openProjects[fromIdx].document.fonts.contains(where: { $0.id == fontID }) else { return }

        confirmMoveFont = FontMoveRequest(
            fontID: fontID,
            fromProjectID: fromProjectID,
            toProjectID: toProjectID
        )
    }

    func confirmMoveFontAction() {
        guard let request = confirmMoveFont else { return }
        confirmMoveFont = nil
        moveFont(
            fontID: request.fontID,
            fromProjectID: request.fromProjectID,
            toProjectID: request.toProjectID
        )
    }

    func moveFont(fontID: String, fromProjectID: String, toProjectID: String) {
        guard fromProjectID != toProjectID,
              let fromIdx = openProjects.firstIndex(where: { $0.id == fromProjectID }),
              let toIdx = openProjects.firstIndex(where: { $0.id == toProjectID }),
              let fontIdx = openProjects[fromIdx].document.fonts.firstIndex(where: { $0.id == fontID }) else { return }

        let font = openProjects[fromIdx].document.fonts[fontIdx]
        let normalizedPath = Self.normalizedPath(URL(fileURLWithPath: font.sourcePath))
        if openProjects[toIdx].document.fonts.contains(where: {
            Self.normalizedPath(URL(fileURLWithPath: $0.sourcePath)) == normalizedPath
        }) {
            postStatusMessage("Already in target project — \(fontBasename(for: font))")
            return
        }

        openProjects[fromIdx].document.fonts.remove(at: fontIdx)
        mergeNamingOrder(for: font, intoProjectAt: toIdx)
        openProjects[toIdx].document.fonts.append(font)
        openProjects[toIdx].document.modified = Date()

        if openProjects[fromIdx].document.fonts.isEmpty {
            closeProject(id: fromProjectID, force: true)
        } else if openProjects[fromIdx].selectedFontID == fontID {
            openProjects[fromIdx].selectedFontID = openProjects[fromIdx].document.fonts.first?.id
        }

        activateProject(id: toProjectID)
        selectFont(id: fontID)
        markProjectFileDirty(projectID: fromProjectID)
        markProjectFileDirty(projectID: toProjectID)
        publishOpenProjects()
        refreshCanSave()
        regeneratePlan()
        postStatusMessage("Moved \(fontBasename(for: font))")
    }

    func requestSplitFontToNewProject(fontID: String, fromProjectID: String) {
        guard canSplitFont(fontID: fontID, fromProjectID: fromProjectID) else { return }
        confirmSplitFont = FontSplitRequest(fontID: fontID, fromProjectID: fromProjectID)
    }

    func confirmSplitFontAction() {
        guard let request = confirmSplitFont else { return }
        confirmSplitFont = nil
        splitFontToNewProject(fontID: request.fontID, fromProjectID: request.fromProjectID)
    }

    func splitFontToNewProject(fontID: String, fromProjectID: String) {
        guard canSplitFont(fontID: fontID, fromProjectID: fromProjectID),
              let fromIdx = openProjects.firstIndex(where: { $0.id == fromProjectID }),
              let fontIdx = openProjects[fromIdx].document.fonts.firstIndex(where: { $0.id == fontID }) else { return }

        let sourceDoc = openProjects[fromIdx].document
        let font = openProjects[fromIdx].document.fonts.remove(at: fontIdx)

        var naming = sourceDoc.naming
        naming.order = Self.mergedNamingOrder(
            projectOrder: naming.order,
            axisTags: font.axes.map(\.tag)
        )

        let newDocument = ProjectDocument(
            schemaVersion: sourceDoc.schemaVersion,
            created: Date(),
            modified: Date(),
            familyLabel: sourceDoc.familyLabel,
            displayName: nil,
            naming: naming,
            template: sourceDoc.template,
            fonts: [font]
        )

        let newOpen = OpenProject(
            document: newDocument,
            selectedFontID: font.id,
            projectFileURL: nil,
            projectFileDirty: true
        )
        openProjects.append(newOpen)

        if openProjects[fromIdx].selectedFontID == fontID {
            openProjects[fromIdx].selectedFontID = openProjects[fromIdx].document.fonts.first?.id
        }
        openProjects[fromIdx].document.modified = Date()
        markProjectFileDirty(projectID: fromProjectID)

        activateProject(id: newOpen.id)
        selectFont(id: font.id)
        publishOpenProjects()
        refreshCanSave()
        regeneratePlan()
        postStatusMessage("Moved \(fontBasename(for: font)) to new project")
    }

    func requestCombineProjects(sourceID: String, intoTargetID targetID: String) {
        guard sourceID != targetID,
              openProjects.contains(where: { $0.id == sourceID }),
              openProjects.contains(where: { $0.id == targetID }) else { return }

        confirmCombineProjects = ProjectCombineRequest(
            sourceProjectID: sourceID,
            targetProjectID: targetID
        )
    }

    func confirmCombineProjectsAction() {
        guard let request = confirmCombineProjects else { return }
        confirmCombineProjects = nil
        combineProjects(sourceID: request.sourceProjectID, intoTargetID: request.targetProjectID)
    }

    func combineProjects(sourceID: String, intoTargetID targetID: String) {
        guard sourceID != targetID,
              let sourceIdx = openProjects.firstIndex(where: { $0.id == sourceID }),
              let targetIdx = openProjects.firstIndex(where: { $0.id == targetID }) else { return }

        let sourceFonts = openProjects[sourceIdx].document.fonts
        var movedCount = 0
        var skippedCount = 0
        var firstMovedFontID: String?

        for font in sourceFonts {
            let normalizedPath = Self.normalizedPath(URL(fileURLWithPath: font.sourcePath))
            if openProjects[targetIdx].document.fonts.contains(where: {
                Self.normalizedPath(URL(fileURLWithPath: $0.sourcePath)) == normalizedPath
            }) {
                skippedCount += 1
                continue
            }

            mergeNamingOrder(for: font, intoProjectAt: targetIdx)
            openProjects[targetIdx].document.fonts.append(font)
            if firstMovedFontID == nil {
                firstMovedFontID = font.id
            }
            movedCount += 1
        }

        openProjects[targetIdx].document.modified = Date()
        markProjectFileDirty(projectID: targetID)
        closeProject(id: sourceID, force: true)

        if movedCount > 0 {
            activateProject(id: targetID)
            if let firstMovedFontID {
                selectFont(id: firstMovedFontID)
            }
            publishOpenProjects()
            refreshCanSave()
            regeneratePlan()
        }

        if movedCount > 0, skippedCount > 0 {
            postStatusMessage(
                "Combined \(movedCount) file\(movedCount == 1 ? "" : "s"); skipped \(skippedCount) duplicate\(skippedCount == 1 ? "" : "s")"
            )
        } else if movedCount > 0 {
            postStatusMessage("Combined \(movedCount) file\(movedCount == 1 ? "" : "s") into project")
        } else {
            postStatusMessage("Nothing to combine — all files already in project")
        }
    }

    private func mergeNamingOrder(for font: FontDocument, intoProjectAt projectIndex: Int) {
        openProjects[projectIndex].document.naming.order = Self.mergedNamingOrder(
            projectOrder: openProjects[projectIndex].document.naming.order,
            axisTags: font.axes.map(\.tag)
        )
    }

    func requestCloseProject(id: String) {
        guard openProjects.contains(where: { $0.id == id }) else { return }
        if projectNeedsCloseConfirmation(projectID: id) {
            confirmCloseProjectID = id
            return
        }
        closeProject(id: id, force: true)
    }

    func projectNeedsCloseConfirmation(projectID: String) -> Bool {
        guard let project = openProject(for: projectID) else { return false }
        return project.projectFileDirty || project.document.fonts.contains(where: \.dirty)
    }

    func firstProjectNeedingCloseConfirmation() -> String? {
        openProjects.first(where: { projectNeedsCloseConfirmation(projectID: $0.id) })?.id
    }

    func confirmCloseProjectDiscardAction() {
        guard let id = confirmCloseProjectID else { return }
        confirmCloseProjectID = nil
        closeProject(id: id, force: true)
    }

    func confirmCloseProjectSaveAction() {
        guard let projectID = confirmCloseProjectID,
              let open = openProject(for: projectID) else { return }
        if let url = open.projectFileURL {
            Task { @MainActor in
                await self.saveProject(document: open.document, to: url, projectID: projectID)
                if self.openProject(for: projectID)?.projectFileDirty == false {
                    self.confirmCloseProjectID = nil
                    self.closeProject(id: projectID, force: true)
                }
            }
        } else {
            confirmCloseProjectID = projectID
            presentSaveProjectAsPanelForClose(projectID: projectID)
        }
    }

    private func presentSaveProjectAsPanelForClose(projectID: String) {
        guard let open = openProject(for: projectID) else { return }
        let panel = NSSavePanel()
        panel.title = "Save Project Before Closing"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.varfontProject]
        panel.nameFieldStringValue = defaultProjectFilename(for: open)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let normalized = Self.normalizedProjectFileURL(url)
            Task { @MainActor in
                await self?.saveProject(document: open.document, to: normalized, projectID: projectID)
                if self?.openProject(for: projectID)?.projectFileDirty == false {
                    self?.confirmCloseProjectID = nil
                    self?.closeProject(id: projectID, force: true)
                }
            }
        }
    }

    func confirmCloseProjectAction() {
        confirmCloseProjectDiscardAction()
    }

    func closeProject(id: String, force: Bool) {
        guard let idx = openProjects.firstIndex(where: { $0.id == id }) else { return }
        if !force, projectNeedsCloseConfirmation(projectID: id) {
            confirmCloseProjectID = id
            return
        }

        for font in openProjects[idx].document.fonts {
            removeSourceBookmark(fontID: font.id)
        }
        openProjects.remove(at: idx)
        clearSaveReviewState(forProjectID: id)

        if openProjects.isEmpty {
            activeProjectID = nil
            selectedFontID = nil
            instancePlan = nil
            instanceListDisplay = .empty
            canSave = false
            return
        }

        if activeProjectID == id {
            let neighborIndex = min(idx, openProjects.count - 1)
            activeProjectID = openProjects[neighborIndex].id
        }

        selectedInstanceKey = nil
        selectedInstanceKeys = []
        selectedAxisStopID = nil
        refreshCanSave()
        regeneratePlan()
    }

    func revealActiveFontInFinder() {
        guard let path = selectedFont?.sourcePath else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func revealFontInFinder(fontID: String, projectID: String) {
        guard let project = openProjects.first(where: { $0.id == projectID }),
              let font = project.document.fonts.first(where: { $0.id == fontID }) else { return }
        NSWorkspace.shared.selectFile(font.sourcePath, inFileViewerRootedAtPath: "")
    }

    func removeFontConfirmationMessage(for request: FontRemovalRequest) -> String {
        guard let font = fontDocument(fontID: request.fontID, projectID: request.projectID) else {
            return "Remove this file from the project?"
        }
        let name = fontBasename(for: font)
        if font.dirty {
            return "Remove \(name)? This file has unsaved changes."
        }
        return "Remove \(name) from this project?"
    }

    func moveFontConfirmationMessage(for request: FontMoveRequest) -> String {
        guard let font = fontDocument(fontID: request.fontID, projectID: request.fromProjectID),
              let target = openProjects.first(where: { $0.id == request.toProjectID }) else {
            return "Move this file to another project?"
        }
        let name = fontBasename(for: font)
        let targetName = projectTabLabel(for: target)
        if font.dirty {
            return "Move \(name) into \(targetName)? This file has unsaved changes."
        }
        return "Move \(name) into \(targetName)?"
    }

    func splitFontConfirmationMessage(for request: FontSplitRequest) -> String {
        guard let font = fontDocument(fontID: request.fontID, projectID: request.fromProjectID) else {
            return "Move this file to a new project?"
        }
        let name = fontBasename(for: font)
        if font.dirty {
            return "Move \(name) to a new project? This file has unsaved changes."
        }
        return "Move \(name) to a new project?"
    }

    func combineProjectsConfirmationMessage(for request: ProjectCombineRequest) -> String {
        guard let source = openProjects.first(where: { $0.id == request.sourceProjectID }),
              let target = openProjects.first(where: { $0.id == request.targetProjectID }) else {
            return "Combine these projects?"
        }
        let sourceName = projectTabLabel(for: source)
        let targetName = projectTabLabel(for: target)
        let fileCount = source.document.fonts.count
        let hasDirtyFiles = source.document.fonts.contains(where: \.dirty)
            || target.document.fonts.contains(where: \.dirty)
        let filePhrase = "\(fileCount) file\(fileCount == 1 ? "" : "s")"
        if hasDirtyFiles {
            return "Move \(filePhrase) from \(sourceName) into \(targetName) and close \(sourceName)? One or more files have unsaved changes."
        }
        return "Move \(filePhrase) from \(sourceName) into \(targetName) and close \(sourceName)?"
    }

    func closeProjectConfirmationMessage(for projectID: String) -> String {
        guard let project = openProjects.first(where: { $0.id == projectID }) else {
            return "Close this project?"
        }
        let name = projectTabLabel(for: project)
        let hasProjectDirty = project.projectFileDirty
        let hasFontDirty = project.document.fonts.contains(where: \.dirty)

        switch (hasProjectDirty, hasFontDirty) {
        case (true, true):
            return "Close \(name)? The project file has unsaved changes and one or more font files have unsaved edits. Save the project file here; use Export… to write patched fonts."
        case (true, false):
            return "Close \(name)? The project file has unsaved changes."
        case (false, true):
            return "Close \(name)? One or more font files have unsaved edits — use Export… to write patched fonts."
        case (false, false):
            return "Close \(name)?"
        }
    }

    private func fontDocument(fontID: String, projectID: String) -> FontDocument? {
        openProjects.first(where: { $0.id == projectID })?
            .document.fonts.first(where: { $0.id == fontID })
    }

    func importDroppedFonts(_ urls: [URL], target: WorkspaceDropTarget) async {
        // Dragged Finder URLs are security-scoped; start access before existence checks.
        let scopedAccess = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer {
            for (url, accessing) in scopedAccess where accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let projectURLs = Self.collectProjectURLs(from: urls).filter { url in
            let path = url.path
            return !path.contains("/TemporaryItems/") && !path.contains("/VarFontDrop/")
        }
        if projectURLs.isEmpty,
           urls.contains(where: { Self.isProjectFile($0) }) {
            postStatusMessage("Couldn't open that project drop — use File → Open Project…")
        }
        for projectURL in projectURLs {
            await openProjectFile(at: projectURL)
        }

        let valid = Self.collectFontURLs(from: urls)
        guard !valid.isEmpty else {
            if projectURLs.isEmpty {
                postStatusMessage("No supported font or project files")
            }
            return
        }

        switch target {
        case .newProject:
            await createProjectWithFonts(valid)
        case .project(let projectID):
            for url in valid {
                await addFont(at: url, toProjectID: projectID, selectAfterAdd: false)
            }
            selectMasterFont(for: projectID)
        case .reorderFont, .reorderFontEnd:
            break
        }
    }

    /// First font opens the project tab; remaining fonts are added to it.
    func createProjectWithFonts(_ urls: [URL]) async {
        guard let first = urls.first else { return }
        await createProject(from: first)
        guard let projectID = activeProjectID else { return }
        for url in urls.dropFirst() {
            await addFont(at: url, toProjectID: projectID, selectAfterAdd: false)
        }
        selectMasterFont(for: projectID)
    }

    func suggestsSameFamily(analysis: FontAnalysis, project: ProjectDocument) -> Bool {
        let family = analysis.source.familyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = project.familyLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !family.isEmpty, !label.isEmpty else { return false }
        return label.contains(family) || family.contains(label)
    }

    func suggestedDropProjectID(for analysis: FontAnalysis) -> String? {
        guard let activeProjectID,
              let active = openProjects.first(where: { $0.id == activeProjectID }),
              suggestsSameFamily(analysis: analysis, project: active.document) else {
            return openProjects.first?.id
        }
        return activeProjectID
    }

    // MARK: - Import helpers

    enum FontImportError: LocalizedError {
        case notVariableFont

        var errorDescription: String? {
            switch self {
            case .notVariableFont:
                "Not a variable font — no variation axes found."
            }
        }
    }

    private func validateVariableFont(_ analysis: FontAnalysis) throws {
        if analysis.axes.isEmpty {
            throw FontImportError.notVariableFont
        }
    }

    private func findFont(normalizedPath: String) -> (projectID: String, fontID: String)? {
        for op in openProjects {
            for font in op.document.fonts {
                if Self.normalizedPath(font.sourcePath) == normalizedPath {
                    return (op.id, font.id)
                }
            }
        }
        return nil
    }

    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func refreshCanSave() {
        canSave = project?.fonts.contains(where: \.dirty) ?? false
    }

    func regeneratePlan() {
        guard project != nil, selectedFontID != nil else {
            instancePlan = nil
            instanceListDisplay = .empty
            return
        }
        backfillMissingInferredAxisRoles()
        guard let project else {
            instancePlan = nil
            return
        }
        instancePlan = InstancePlanner.plan(project: project, fontID: selectedFontID!)
        planRevision += 1
        if let key = selectedInstanceKey,
           instancePlan?.instances.contains(where: { $0.key == key }) != true {
            selectedInstanceKey = instancePlan?.instances.first?.key
        }
        refreshInstanceListDisplay()
    }

    func setInstanceIncluded(_ key: String, included: Bool) {
        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }
        var font = project.fonts[fontIndex]
        if included {
            font.excludedInstanceKeys.removeAll { $0 == key }
        } else if !font.excludedInstanceKeys.contains(key) {
            font.excludedInstanceKeys.append(key)
        }
        font.dirty = true
        project.fonts[fontIndex] = font
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func setAxisInstanceGridEnabled(tag: String, enabled: Bool) {
        guard let axis = selectedFont?.axes.first(where: { $0.tag == tag }),
              !axis.isDesignRecordOnly else { return }
        updateAxisRole(tag: tag, role: enabled ? .instance : .statOnly)
    }

    func setAxisStatOnly(tag: String, statOnly: Bool) {
        setAxisInstanceGridEnabled(tag: tag, enabled: !statOnly)
    }

    func axisParticipatesInInstanceGrid(tag: String) -> Bool {
        if NamingToken.isClarifier(tag) { return false }
        return selectedFont?.axes.first(where: { $0.tag == tag })?.role == .instance
    }

    func isRegistrationNamingAxis(tag: String) -> Bool {
        selectedFont?.axes.first(where: { $0.tag == tag })?.isDesignRecordOnly == true
    }

    func clarifierCoveredByRegistration(category: FileClarifierCategory, for fontID: String) -> Bool {
        guard let font = font(forProjectID: activeProjectID ?? "", fontID: fontID) else { return false }
        return RegistrationAxisSupport.clarifierCategoriesCoveredByRegistration(font: font).contains(category)
    }

    // MARK: - File clarifiers

    func fileRole(for fontID: String) -> FileRole? {
        project?.fonts.first { $0.id == fontID }?.fileRole
    }

    var selectedFileRole: FileRole? {
        guard let selectedFontID else { return nil }
        return fileRole(for: selectedFontID)
    }

    var isSelectedFontMaster: Bool {
        selectedFileRole?.kind == .master
    }

    func clarifierLabels(for fontID: String) -> [FileClarifier] {
        fileRole(for: fontID)?.clarifiers ?? []
    }

    func masterFontID(for projectID: String) -> String? {
        guard let open = openProject(for: projectID) else { return nil }
        return open.document.fonts.first { $0.fileRole?.kind == .master }?.id
            ?? open.document.fonts.first?.id
    }

    func setFontAsMaster(fontID: String) {
        guard var project else { return }
        pushUndoSnapshot()
        applyMasterFont(fontID: fontID, to: &project)
        syncProjectNameFromMaster(on: &project, masterFontID: fontID)
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func requestSetAsMaster(fontID: String) {
        confirmSetAsMasterFontID = fontID
    }

    func confirmSetAsMasterAction() {
        guard let fontID = confirmSetAsMasterFontID else { return }
        confirmSetAsMasterFontID = nil
        setFontAsMaster(fontID: fontID)
    }

    func requestPushMasterAxisTree() {
        confirmPushAxisTree = true
    }

    func confirmPushAxisTreeAction() {
        confirmPushAxisTree = false
        pushMasterAxisTreeToAllFonts()
    }

    func dismissPersistentSaveError() {
        persistentSaveError = nil
    }

    private func postSaveFailure(_ message: String) {
        persistentSaveError = message
        postStatusMessage(message)
    }

    private func promoteFirstFontToMaster(projectIndex: Int) {
        guard let firstID = openProjects[projectIndex].document.fonts.first?.id else { return }
        guard masterFontID(for: openProjects[projectIndex].id) != firstID else { return }
        applyMasterFont(fontID: firstID, to: &openProjects[projectIndex].document)
        syncProjectNameFromMaster(on: &openProjects[projectIndex].document, masterFontID: firstID)
        openProjects[projectIndex].document.modified = Date()
    }

    private func applyMasterFont(fontID: String, to document: inout ProjectDocument) {
        for index in document.fonts.indices {
            if document.fonts[index].id == fontID {
                document.fonts[index].fileRole = .master()
            } else {
                var role = document.fonts[index].fileRole ?? .variant(masterFontID: fontID)
                role.kind = .variant
                role.masterFontID = fontID
                document.fonts[index].fileRole = role
            }
            document.fonts[index].dirty = true
        }
        // Master always leads the FILE row / inspector list.
        if let index = document.fonts.firstIndex(where: { $0.id == fontID }), index != 0 {
            let master = document.fonts.remove(at: index)
            document.fonts.insert(master, at: 0)
        }
    }

    func setFileClarifiers(_ clarifiers: [FileClarifier], for fontID: String) {
        mutateFont(id: fontID) { font in
            var role = font.fileRole ?? .variant(masterFontID: masterFontID(for: activeProjectID ?? "") ?? "")
            if role.kind == .master, !clarifiers.isEmpty {
                role.kind = .variant
                role.masterFontID = masterFontID(for: activeProjectID ?? "")
            }
            role.clarifiers = clarifiers
            font.fileRole = role
        }
    }

    func setFileClarifier(category: FileClarifierCategory, label: String, for fontID: String) {
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == fontID }) else { return }
        pushUndoSnapshot()
        var role = project.fonts[index].fileRole ?? .variant(masterFontID: masterFontID(for: activeProjectID ?? "") ?? "")
        role.clarifiers.removeAll { $0.category == category }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            role.clarifiers.append(FileClarifier(category: category, label: trimmed))
        }
        project.fonts[index].fileRole = role
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func removeFileClarifier(category: FileClarifierCategory, for fontID: String) {
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == fontID }) else { return }
        pushUndoSnapshot()
        var role = project.fonts[index].fileRole ?? .master()
        role.clarifiers.removeAll { $0.category == category }
        project.fonts[index].fileRole = role
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func clearFileClarifiers(for fontID: String) {
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == fontID }) else { return }
        guard !(project.fonts[index].fileRole?.clarifiers.isEmpty ?? true) else { return }
        pushUndoSnapshot()
        var role = project.fonts[index].fileRole ?? .master()
        role.clarifiers = []
        role.elidedFallbackOverride = nil
        project.fonts[index].fileRole = role
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func familyPSPrefix(for fontID: String) -> String {
        font(forProjectID: activeProjectID ?? "", fontID: fontID)?.options.familyPSPrefix ?? ""
    }

    func setFamilyPSPrefix(_ value: String, for fontID: String) {
        let resolved = normalizedProjectNaming(value)
        guard var project, let projectID = activeProjectID else { return }

        // Master is the clean shared stem — edit pushes to every file in the project
        // and stays paired with the project display name.
        let isMaster = isMasterFont(fontID: fontID, projectID: projectID)
        if isMaster {
            pushUndoSnapshot()
            syncProjectDisplayNameAndPrefix(resolved, on: &project)
            project.modified = Date()
            self.project = project
            canSave = true
            regeneratePlan()
        } else {
            mutateFont(id: fontID) { font in
                font.options.familyPSPrefix = resolved
            }
        }
    }

    func setFileStatRegistration(tag: String, value: Double, forFontID fontID: String) {
        mutateFont(id: fontID) { font in
            font.fileStatRegistration[tag] = value
        }
    }

    func slopeClarifierSupersededByRegistration(for fontID: String) -> Bool {
        clarifierCoveredByRegistration(category: .slope, for: fontID)
    }

    func setElidedFallbackOverride(_ value: String?, for fontID: String) {
        mutateFont(id: fontID) { font in
            var role = font.fileRole ?? .master()
            role.elidedFallbackOverride = {
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }()
            font.fileRole = role
        }
    }

    func inferFileClarifiersForSelectedFont() {
        guard let font = selectedFont, let projectID = activeProjectID, var project else { return }
        let fontCount = project.fonts.count
        let role = font.fileRole ?? .variant(masterFontID: masterFontID(for: projectID) ?? "")
        if ClarifierSlotCoverage.isMultiFileMaster(font: font, projectFontCount: fontCount) {
            postStatusMessage("Clarifiers belong on variant files.")
            return
        }

        let analysis: FontAnalysis
        do {
            analysis = try analyzeSourceFont(fontID: font.id, sourcePath: font.sourcePath)
        } catch {
            postStatusMessage("Could not read source font: \(error.localizedDescription)")
            return
        }
        let prefixEmpty = project.fonts.first(where: { $0.id == font.id })?
            .options.familyPSPrefix?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        let inferredPrefix = analysis.source.familyPSPrefix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixWouldUpdate = prefixEmpty
            && !(inferredPrefix?.isEmpty ?? true)

        let canInferClarifiers = ClarifierSlotCoverage.hasEditableInferSlots(
            font: font,
            projectFontCount: fontCount
        )

        if !canInferClarifiers, !prefixWouldUpdate {
            postStatusMessage("No file-level clarifiers needed — axis and registration naming cover this file.")
            return
        }

        let inferred = canInferClarifiers
            ? FileClarifierInference.infer(
                sourceURL: URL(fileURLWithPath: font.sourcePath),
                analysis: analysis,
                font: font
            )
            : FileClarifierInferenceResult(clarifiers: [], elidedFallbackOverride: nil)

        if inferred.clarifiers.isEmpty, !prefixWouldUpdate {
            postStatusMessage("No clarifiers matched the filename.")
            return
        }

        pushUndoSnapshot()
        guard let index = project.fonts.firstIndex(where: { $0.id == font.id }) else { return }
        var updatedRole = project.fonts[index].fileRole ?? role
        if canInferClarifiers {
            updatedRole.clarifiers = inferred.clarifiers
            updatedRole.elidedFallbackOverride = inferred.elidedFallbackOverride
        }
        if prefixWouldUpdate, let prefix = inferredPrefix, !prefix.isEmpty {
            project.fonts[index].options.familyPSPrefix = prefix
        }
        project.fonts[index].fileRole = updatedRole
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()

        if inferred.clarifiers.isEmpty {
            postStatusMessage("Updated PostScript prefix from font metadata.")
        } else {
            let count = inferred.clarifiers.count
            postStatusMessage("Inferred \(count) file naming label\(count == 1 ? "" : "s").")
        }
    }

    func pushAxisTreeConfirmationMessage() -> String {
        let count = max((project?.fonts.count ?? 1) - 1, 0)
        if count == 1 {
            return "This will overwrite the axis-tree layout on 1 file with the master's layout."
        }
        return "This will overwrite the axis-tree layout on \(count) files with the master's layout."
    }

    func pushMasterAxisTreeToAllFonts() {
        guard let project, let projectID = activeProjectID,
              let masterID = masterFontID(for: projectID),
              let masterFont = project.fonts.first(where: { $0.id == masterID }) else { return }
        pushUndoSnapshot()
        guard var updated = self.project else { return }
        for index in updated.fonts.indices where updated.fonts[index].id != masterID {
            updated.fonts[index].axes = AxisTreeMerge.mergeAxesFromMaster(
                master: masterFont.axes,
                into: updated.fonts[index].axes,
                syncRoles: updated.template.syncRoles,
                targetFileStatRegistration: updated.fonts[index].fileStatRegistration,
                targetIsItalicFile: RegistrationAxisSupport.isItalicFile(font: updated.fonts[index])
            )
            updated.fonts[index].dirty = true
        }
        updated.template.axes = masterFont.axes
        updated.modified = Date()
        self.project = updated
        canSave = true
        regeneratePlan()
        postStatusMessage("Pushed axis tree from master to \(updated.fonts.count - 1) file(s)")
    }

    private func mutateFont(id fontID: String, _ mutate: (inout FontDocument) -> Void) {
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == fontID }) else { return }
        pushUndoSnapshot()
        mutate(&project.fonts[index])
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    private func normalizedProjectNaming(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applySharedFamilyPSPrefix(_ prefix: String?, to document: inout ProjectDocument) {
        for index in document.fonts.indices {
            document.fonts[index].options.familyPSPrefix = prefix
            document.fonts[index].dirty = true
        }
    }

    private func syncProjectDisplayNameAndPrefix(_ name: String?, on document: inout ProjectDocument) {
        document.displayName = name
        applySharedFamilyPSPrefix(name, to: &document)
    }

    /// When master changes, project name follows the new master's prefix and pushes downstream.
    private func syncProjectNameFromMaster(on document: inout ProjectDocument, masterFontID: String) {
        guard let master = document.fonts.first(where: { $0.id == masterFontID }) else { return }
        if let prefix = normalizedProjectNaming(master.options.familyPSPrefix ?? "") {
            syncProjectDisplayNameAndPrefix(prefix, on: &document)
            return
        }
        if let displayName = document.displayName, !displayName.isEmpty {
            applySharedFamilyPSPrefix(displayName, to: &document)
        }
    }

    func updateAxisRole(tag: String, role: AxisRole) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == tag }) else { return }
            if font.axes[axisIndex].isDesignRecordOnly { return }
            font.axes[axisIndex].role = role
        }
    }

    func updateAxisDisplayName(tag: String, name: String) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == tag }) else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            font.axes[axisIndex].displayName = trimmed.isEmpty ? nil : trimmed
        }
    }

    func updateAxisStopName(axisTag: String, stopID: String, name: String) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            font.axes[axisIndex].values[stopIndex].name = name
        }
    }

    func updateAxisStopElidable(axisTag: String, stopID: String, elidable: Bool) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            if elidable {
                for index in font.axes[axisIndex].values.indices {
                    font.axes[axisIndex].values[index].elidable = font.axes[axisIndex].values[index].id == stopID
                }
            } else {
                font.axes[axisIndex].values[stopIndex].elidable = false
            }
        }
    }

    func updateAxisStopValue(axisTag: String, stopID: String, value: Double) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            let axis = font.axes[axisIndex]
            var clamped = value
            if let min = axis.min { clamped = max(clamped, min) }
            if let max = axis.max { clamped = min(clamped, max) }
            let previousValue = font.axes[axisIndex].values[stopIndex].value
            let wasRegistered = font.fileStatRegistration[axisTag]
                .map { AxisCoordinate.valuesEqual($0, previousValue) } ?? false
            font.axes[axisIndex].values[stopIndex].value = clamped
            font.axes[axisIndex].values.sort { $0.value < $1.value }
            if wasRegistered {
                font.fileStatRegistration[axisTag] = clamped
            }
        }
    }

    func updateAxisStopRangeMin(axisTag: String, stopID: String, rangeMin: Double) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            let axis = font.axes[axisIndex]
            var clamped = rangeMin
            if let min = axis.min { clamped = max(clamped, min) }
            if let max = axis.max { clamped = min(clamped, max) }
            font.axes[axisIndex].values[stopIndex].rangeMin = clamped
        }
    }

    func updateAxisStopRangeMax(axisTag: String, stopID: String, rangeMax: Double) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            let axis = font.axes[axisIndex]
            var clamped = rangeMax
            if let min = axis.min { clamped = max(clamped, min) }
            if let max = axis.max { clamped = min(clamped, max) }
            font.axes[axisIndex].values[stopIndex].rangeMax = clamped
        }
    }

    func updateAxisStopStatFormat(
        axisTag: String,
        stopID: String,
        format: Int,
        linkTargetStopID: String? = nil
    ) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            var stop = font.axes[axisIndex].values[stopIndex]
            stop.statFormat = format
            switch format {
            case 2:
                stop.linkedValue = nil
                if stop.rangeMin == nil {
                    stop.rangeMin = max((font.axes[axisIndex].min ?? stop.value) , stop.value - 20)
                }
                if stop.rangeMax == nil {
                    stop.rangeMax = min((font.axes[axisIndex].max ?? stop.value + 20), stop.value + 20)
                }
            case 3:
                stop.rangeMin = nil
                stop.rangeMax = nil
                if let linkTargetStopID,
                   let target = font.axes[axisIndex].values.first(where: { $0.id == linkTargetStopID }) {
                    stop.linkedValue = target.value
                }
            default:
                stop.statFormat = 1
                stop.rangeMin = nil
                stop.rangeMax = nil
                stop.linkedValue = nil
            }
            font.axes[axisIndex].values[stopIndex] = stop
        }
    }

    func updateAxisStopLinkedTarget(axisTag: String, stopID: String, linkTargetStopID: String) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }),
                  let target = font.axes[axisIndex].values.first(where: { $0.id == linkTargetStopID }) else { return }
            font.axes[axisIndex].values[stopIndex].statFormat = 3
            font.axes[axisIndex].values[stopIndex].linkedValue = target.value
        }
    }

    var coordinateDisplayMode: CoordinateDisplayMode {
        project?.coordinateDisplay ?? .reference
    }

    func setCoordinateDisplay(_ mode: CoordinateDisplayMode) {
        guard var project else { return }
        project.coordinateDisplay = mode
        self.project = project
        markProjectFileDirty()
    }

    func nameidStrategy(forProjectID projectID: String) -> NameIDStrategy {
        openProjects.first(where: { $0.id == projectID })?.document.nameidStrategy ?? .preserve
    }

    func setNameIDStrategy(forProjectID projectID: String, strategy: NameIDStrategy) {
        guard let index = openProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var document = openProjects[index].document
        guard document.nameidStrategy != strategy else { return }
        document.nameidStrategy = strategy
        document.syncNameIDStrategyToFonts()
        openProjects[index].document = document
        if activeProjectID == projectID {
            project = document
        }
        markProjectFileDirty(projectID: projectID)

        let fontIDs = document.fonts.map(\.id)
        for fontID in fontIDs {
            clearSaveReviewState(forProjectID: projectID, fontID: fontID)
        }
        for fontID in fontIDs {
            refreshCommitDiffPreview(forProjectID: projectID, fontID: fontID)
        }
    }

    func displayStopValue(for axis: AxisDefinition, native: Double) -> Double {
        guard coordinateDisplayMode == .reference,
              AxisLadderAlignment.supportsAlignment(axis.tag),
              (axis.referenceMapping ?? .identity) != .identity else {
            return native
        }
        return AxisReferenceMapping.nativeToReference(native, axis: axis)
    }

    func showsNativeFootnote(for axis: AxisDefinition, native: Double) -> Bool {
        guard coordinateDisplayMode == .reference,
              AxisLadderAlignment.supportsAlignment(axis.tag),
              (axis.referenceMapping ?? .identity) != .identity else {
            return false
        }
        let reference = AxisReferenceMapping.nativeToReference(native, axis: axis)
        return !AxisCoordinate.valuesEqual(reference, native)
    }

    func commitStopDisplayValue(axisTag: String, stopID: String, displayValue: Double) {
        guard let axis = selectedFont?.axes.first(where: { $0.tag == axisTag }) else { return }
        let native = nativeStopValue(fromDisplayValue: displayValue, for: axis)
        updateAxisStopValue(axisTag: axisTag, stopID: stopID, value: native)
    }

    func nativeStopValue(fromDisplayText text: String, for axis: AxisDefinition) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let display = Double(trimmed) else { return nil }
        return nativeStopValue(fromDisplayValue: display, for: axis)
    }

    func nativeStopValue(fromDisplayValue display: Double, for axis: AxisDefinition) -> Double {
        if coordinateDisplayMode == .reference,
           AxisLadderAlignment.supportsAlignment(axis.tag),
           (axis.referenceMapping ?? .identity) != .identity {
            return AxisReferenceMapping.referenceToNative(display, axis: axis)
        }
        return display
    }

    func setFixFvarDefault(_ enabled: Bool, for fontID: String) {
        mutateFont(id: fontID) { font in
            font.options.fixFvarDefault = enabled
        }
    }

    func toggleAxisStopElidable(axisTag: String, stopID: String) {
        guard let axis = selectedFont?.axes.first(where: { $0.tag == axisTag }),
              let stop = axis.values.first(where: { $0.id == stopID }) else { return }
        updateAxisStopElidable(axisTag: axisTag, stopID: stopID, elidable: !stop.elidable)
    }

    func undo() {
        guard let current = project, let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        project = previous
        if let fontID = selectedFontID,
           project?.fonts.contains(where: { $0.id == fontID }) != true {
            selectedFontID = project?.fonts.first?.id
        }
        canSave = project?.fonts.contains(where: \.dirty) ?? false
        markProjectFileDirty()
        refreshCanSave()
        regeneratePlan()
    }

    func redo() {
        guard let current = project, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        project = next
        canSave = next.fonts.contains(where: \.dirty)
        markProjectFileDirty()
        regeneratePlan()
    }

    private func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func pushUndoSnapshot() {
        guard let project else { return }
        undoStack.append(project)
        if undoStack.count > 100 {
            undoStack = Array(undoStack.suffix(100))
        }
        redoStack.removeAll()
        markProjectFileDirty()
    }

    func removeAxisStop(axisTag: String, stopID: String) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            font.axes[axisIndex].values.removeAll { $0.id == stopID }
        }
        if selectedAxisStopID == stopID {
            selectedAxisStopID = nil
        }
    }

    func suggestedNewStopValue(for axis: AxisDefinition, excludingStopID: String) -> Double {
        AxisStopSuggestions.suggestedValue(for: axis, excludingStopIDs: [excludingStopID])
    }

    func insertAxisStop(
        axisTag: String,
        value: Double,
        name: String,
        statFormat: Int = 1,
        rangeMin: Double? = nil,
        rangeMax: Double? = nil,
        linkedStopID: String? = nil
    ) {
        var addedStopID: String?
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            let stopID = "\(axisTag)-\(UUID().uuidString.prefix(8))"
            var linkedValue: Double?
            if statFormat == 3, let linkedStopID,
               let target = font.axes[axisIndex].values.first(where: { $0.id == linkedStopID }) {
                linkedValue = target.value
            }
            let stop = AxisValue(
                id: stopID,
                value: value,
                name: name,
                elidable: false,
                statFormat: statFormat,
                rangeMin: rangeMin,
                rangeMax: rangeMax,
                linkedValue: linkedValue
            )
            font.axes[axisIndex].values.append(stop)
            font.axes[axisIndex].values.sort { $0.value < $1.value }
            addedStopID = stopID
        }
        selectedAxisStopID = addedStopID
    }

    /// Replaces every stop on `axisTag` with the given values (name = numeric value), sorted
    /// ascending. Used by the quick-fill tool, which — unlike `insertAxisStop` — is meant to be
    /// re-run freely to tweak a fill without requiring an undo first.
    func replaceAxisStops(axisTag: String, values: [Double]) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  font.axes[axisIndex].role == .instance,
                  !font.axes[axisIndex].isDesignRecordOnly else { return }
            font.axes[axisIndex].values = values.map { rawValue in
                let value = AxisCoordinateFormat.canonical(rawValue)
                return AxisValue(
                    id: "\(axisTag)-\(UUID().uuidString.prefix(8))",
                    value: value,
                    name: AxisStopSuggestions.formatValue(value),
                    elidable: false,
                    statFormat: 1,
                    rangeMin: nil,
                    rangeMax: nil,
                    linkedValue: nil
                )
            }.sorted { $0.value < $1.value }
        }
    }

    func validateAxisStopValue(_ value: Double, for axis: AxisDefinition, excludingStopID: String? = nil) -> String? {
        if axis.hasFvarScale {
            if let min = axis.min, value < min {
                return "Value must be at least \(StudioFormatting.axisValue(min))."
            }
            if let max = axis.max, value > max {
                return "Value must be at most \(StudioFormatting.axisValue(max))."
            }
        }
        let duplicate = axis.values.contains { stop in
            stop.id != excludingStopID && AxisCoordinate.valuesEqual(stop.value, value)
        }
        if duplicate {
            return "Another stop already uses this value."
        }
        return nil
    }

    private func mutateSelectedFont(
        recordUndo: Bool = true,
        debouncePlan: Bool = false,
        _ mutate: (inout FontDocument) -> Void
    ) {
        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }
        if recordUndo {
            pushUndoSnapshot()
        }
        mutate(&project.fonts[fontIndex])
        project.fonts[fontIndex].dirty = true
        project.modified = Date()
        let shouldDebouncePlan = debouncePlan
        Task { @MainActor in
            self.project = project
            self.canSave = true
            if shouldDebouncePlan {
                self.scheduleDebouncedPlanRegeneration()
            } else {
                self.debouncedPlanTask?.cancel()
                self.regeneratePlan()
            }
        }
    }

    private func backfillMissingInferredAxisRoles() {
        guard var project,
              let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else { return }

        let sourcePath = project.fonts[fontIndex].sourcePath
        let fontID = project.fonts[fontIndex].id
        let analysis: FontAnalysis
        do {
            analysis = try analyzeSourceFont(fontID: fontID, sourcePath: sourcePath)
        } catch {
            postStatusMessage("Could not read source font: \(error.localizedDescription)")
            return
        }

        let existingTags = Set(project.fonts[fontIndex].axes.map(\.tag))
        let missingDesignAxes = analysis.axes.filter {
            $0.roleInferred == .designRecordOnly && !existingTags.contains($0.tag)
        }
        let needsRoleBackfill = project.fonts[fontIndex].axes.contains { $0.roleInferred == nil }
        guard needsRoleBackfill || !missingDesignAxes.isEmpty else { return }

        var changed = false
        for axisIndex in project.fonts[fontIndex].axes.indices {
            guard project.fonts[fontIndex].axes[axisIndex].roleInferred == nil else { continue }
            let tag = project.fonts[fontIndex].axes[axisIndex].tag
            guard let analyzed = analysis.axes.first(where: { $0.tag == tag }) else { continue }
            project.fonts[fontIndex].axes[axisIndex].roleInferred = analyzed.roleInferred
            changed = true
        }

        if !missingDesignAxes.isEmpty {
            for analyzed in missingDesignAxes {
                project.fonts[fontIndex].axes.append(ProjectImporter.axisDefinition(from: analyzed))
            }
            let order = analysis.axes.map(\.tag)
            project.fonts[fontIndex].axes.sort {
                let left = order.firstIndex(of: $0.tag) ?? Int.max
                let right = order.firstIndex(of: $1.tag) ?? Int.max
                if left != right { return left < right }
                return $0.tag < $1.tag
            }
            project.fonts[fontIndex].dirty = true
            changed = true
        }

        if changed {
            self.project = project
            regeneratePlan()
        }
    }

    private func scheduleDebouncedPlanRegeneration() {
        debouncedPlanTask?.cancel()
        debouncedPlanTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            regeneratePlan()
        }
    }

    func saveCopy() {
        refreshCommitDiffPreview(presentSheet: true)
    }

    func requestSaveToOriginal() {
        guard canSave else {
            postStatusMessage("Nothing to export — make an edit first.")
            return
        }
        Task {
            guard let projectID = activeProjectID, let fontID = selectedFontID else { return }
            guard let session = await ensureSaveReviewSession(projectID: projectID, fontID: fontID) else { return }
            guard session.preflight.ok else {
                postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
                return
            }
            confirmSaveToOriginal = session
        }
    }

    func confirmSaveToOriginalAction() {
        guard let session = confirmSaveToOriginal,
              let font = font(forProjectID: session.projectID, fontID: session.fontID) else { return }
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
        guard let font = font(forProjectID: session.projectID, fontID: session.fontID) else {
            return "Overwrite the original font file? This cannot be undone."
        }
        return "Overwrite \(URL(fileURLWithPath: font.sourcePath).lastPathComponent)? A .vfstudio-backup copy is written beside the original first."
    }

    /// User-facing: Export — write to `font.outputPath` when set; otherwise open Review (same as Export…).
    func save() {
        guard canSave else {
            postStatusMessage("Nothing to export — make an edit first.")
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
        guard let projectID = activeProjectID, let fontID = selectedFontID else { return false }
        return canSaveToRememberedPath(forProjectID: projectID, fontID: fontID)
    }

    func savedOutputLabel(for font: FontDocument) -> String? {
        guard let outputPath = font.outputPath else { return nil }
        return URL(fileURLWithPath: outputPath).lastPathComponent
    }

    private func rememberedOutputURL(forProjectID projectID: String, fontID: String) -> URL? {
        guard let font = font(forProjectID: projectID, fontID: fontID),
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
        guard let projectID = activeProjectID, let fontID = selectedFontID else { return }

        if let outputURL = rememberedOutputURL(forProjectID: projectID, fontID: fontID),
           let font = font(forProjectID: projectID, fontID: fontID) {
            guard let session = await ensureSaveReviewSession(projectID: projectID, fontID: fontID) else { return }
            guard session.preflight.ok else {
                postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
                return
            }
            if Self.normalizedPath(outputURL) == Self.normalizedPath(URL(fileURLWithPath: font.sourcePath)) {
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
        let targetProjectID = projectID ?? activeProjectID
        guard let targetProjectID,
              let open = openProject(for: targetProjectID) else {
            if presentSheet {
                postStatusMessage("Nothing to save — open a font first.")
            }
            return nil
        }

        let targetFontID = fontID
            ?? saveReviewSelectedFontID(forProjectID: targetProjectID)
            ?? open.selectedFontID
        guard let targetFontID,
              let font = open.document.fonts.first(where: { $0.id == targetFontID }),
              let plan = instancePlan(forProjectID: targetProjectID, fontID: targetFontID) else {
            if presentSheet {
                postStatusMessage("Nothing to save — open a font first.")
            }
            return nil
        }

        let projectDoc = open.document

        let duplicateIncluded = plan.instances.filter { $0.included && $0.duplicate }
        if !duplicateIncluded.isEmpty {
            postStatusMessage("Resolve duplicate instance names before saving.")
            return nil
        }

        guard FileManager.default.fileExists(atPath: font.sourcePath) else {
            postStatusMessage("Source font file is missing — re-open the original file.")
            return nil
        }

        let bookmark = sourceBookmarks[font.id]
        let outputPath = font.outputPath ?? CommitRequestBuilder.suggestedOutputPath(for: font.sourcePath)
        var dryRunRequest = CommitRequestBuilder.make(
            font: font,
            naming: projectDoc.naming,
            plan: plan,
            outputPath: outputPath,
            dryRun: true,
            nameidStrategy: projectDoc.nameidStrategy
        )

        let sessionKey = saveReviewSessionKey(projectID: targetProjectID, fontID: targetFontID)
        saveReviewLoadingKeys.insert(sessionKey)
        defer { saveReviewLoadingKeys.remove(sessionKey) }

        do {
            let analysis = try SourceFontAccess.withReadableSourceURL(
                bookmark: bookmark,
                fallbackPath: font.sourcePath
            ) { sourceURL in
                try FontAnalysisReader.analyzeForCommitDiff(url: sourceURL)
            }
            let helperSourcePath = try SourceFontAccess.helperSourcePath(
                bookmark: bookmark,
                fallbackPath: font.sourcePath,
                fontID: font.id
            )
            dryRunRequest.sourcePath = helperSourcePath
            let result = try await commitService.commit(dryRunRequest, preferWorker: preferWorker)
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
                saveReviewSessionsByKey[sessionKey] = session
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
            saveReviewSessionsByKey[sessionKey] = failedSession
            postStatusMessage(message)
            if presentSheet {
                presentCommitDiffSheet = true
            }
            return failedSession
        } catch {
            postSaveFailure(commitFailureMessage(error))
            return nil
        }
    }

    func dismissCommitDiffSheet() {
        presentCommitDiffSheet = false
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
            postStatusMessage("Exported save plan to \(directory.lastPathComponent)")
        } catch {
            postStatusMessage("JSON export failed: \(error.localizedDescription)")
        }
    }

    func presentSavePanel(for session: CommitPreflightSession) {
        guard let font = font(forProjectID: session.projectID, fontID: session.fontID) else { return }

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
            let normalizedOutput = Self.normalizedPath(url)
            let normalizedSource = Self.normalizedPath(URL(fileURLWithPath: font.sourcePath))
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
            postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
            return
        }

        if usingRememberedPath,
           let url = rememberedOutputURL(forProjectID: session.projectID, fontID: session.fontID),
           let font = font(forProjectID: session.projectID, fontID: session.fontID) {
            if Self.normalizedPath(url) == Self.normalizedPath(URL(fileURLWithPath: font.sourcePath)) {
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
        guard let projectID = projectID ?? activeProjectID,
              let open = openProject(for: projectID) else { return }

        let fontsToWrite = open.document.fonts.filter(\.dirty)
        let targets = fontsToWrite.isEmpty ? open.document.fonts : fontsToWrite
        guard !targets.isEmpty else {
            postStatusMessage("Nothing to export.")
            return
        }

        for font in targets {
            guard let plan = instancePlan(forProjectID: projectID, fontID: font.id) else {
                postStatusMessage("Couldn't prepare the export preview. Try again, or check that the font file hasn't moved or changed.")
                return
            }
            if plan.instances.contains(where: { $0.included && $0.duplicate }) {
                postStatusMessage("Resolve duplicate instance names in \(fontBasename(for: font)) before saving.")
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
                postStatusMessage("Export preview failed for \(fontBasename(for: font)). Check the Review window for details.")
                return
            }
            guard session.preflight.ok else {
                postStatusMessage(session.preflight.errors.first?.message ?? "Export preview failed. Check the Review window for details.")
                return
            }
        }

        var outputURLs: [String: URL] = [:]
        for font in targets {
            if let url = rememberedOutputURL(forProjectID: projectID, fontID: font.id) {
                if url.path == font.sourcePath {
                    postStatusMessage("Export All cannot overwrite originals — use Export to Original… per file.")
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
            if Self.normalizedPath(url) == Self.normalizedPath(URL(fileURLWithPath: font.sourcePath)) {
                postStatusMessage("Export All cannot overwrite originals — use Export to Original… per file.")
                return
            }
        }

        isBusy = true
        defer { isBusy = false }

        for font in targets {
            guard let session = sessions[font.id], let url = outputURLs[font.id] else { continue }
            await performSave(session: session, to: url, manageBusyState: false)
        }

        let folderLabel = outputDirectory?.lastPathComponent
            ?? outputURLs.values.first?.deletingLastPathComponent().lastPathComponent
            ?? "output folder"
        postStatusMessage("Exported \(targets.count) fonts to \(folderLabel)")
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
        if isBusy { return true }
        guard let projectID = activeProjectID else { return false }
        return isSaveReviewLoading(forProjectID: projectID)
    }

    func performSave(
        session: CommitPreflightSession,
        to outputURL: URL,
        inPlace: Bool = false,
        manageBusyState: Bool = true
    ) async {
        guard let projectIndex = openProjects.firstIndex(where: { $0.id == session.projectID }),
              let fontIndex = openProjects[projectIndex].document.fonts.firstIndex(where: { $0.id == session.fontID }) else {
            return
        }

        let originalSourcePath = openProjects[projectIndex].document.fonts[fontIndex].sourcePath
        guard FileManager.default.fileExists(atPath: originalSourcePath) else {
            postStatusMessage("Source font file is missing — re-open the original file.")
            return
        }

        var request = session.baseRequest
        request.outputPath = outputURL.path
        request.originalSourcePath = originalSourcePath
        request.allowInPlace = inPlace
        request.dryRun = false
        request.requestID = UUID().uuidString.lowercased()

        if manageBusyState { isBusy = true }
        defer { if manageBusyState { isBusy = false } }

        do {
            let result = try await commitService.commit(request)
            guard result.ok else {
                let message = result.errors.first?.message ?? "Export failed."
                postStatusMessage(message)
                return
            }

            var project = openProjects[projectIndex].document
            if inPlace {
                SourceFontAccess.invalidateCache(fontID: session.fontID)
                let sourceURL = URL(fileURLWithPath: originalSourcePath)
                registerSourceBookmark(url: sourceURL, fontID: session.fontID)
                project.fonts[fontIndex].outputPath = originalSourcePath
            } else {
                project.fonts[fontIndex].outputPath = outputURL.path
            }
            project.fonts[fontIndex].dirty = false
            openProjects[projectIndex].document = project
            publishOpenProjects()
            if activeProjectID == session.projectID {
                self.project = project
                refreshCanSave()
            }
            clearSaveReviewState(forProjectID: session.projectID, fontID: session.fontID)
            presentCommitDiffSheet = false

            if inPlace {
                let backupName = URL(fileURLWithPath: originalSourcePath).lastPathComponent + ".vfstudio-backup"
                postStatusMessage("Saved to original (backup: \(backupName))")
            } else if let count = result.summary?.instancesWritten {
                postStatusMessage("Saved \(count) instances to \(outputURL.lastPathComponent)")
            } else {
                postStatusMessage("Saved \(outputURL.lastPathComponent)")
            }
        } catch {
            postSaveFailure(commitFailureMessage(error))
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

    static func collectFontURLs(from urls: [URL]) -> [URL] {
        var collected: [URL] = []
        var seen = Set<String>()

        func ingest(_ url: URL) {
            let norm = normalizedPath(url)
            guard !seen.contains(norm) else { return }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

            if isDirectory.boolValue {
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { return }
                for item in contents {
                    ingest(item)
                }
            } else if isFontFile(url) {
                seen.insert(norm)
                collected.append(url.standardizedFileURL)
            }
        }

        for url in urls {
            ingest(url)
        }
        return collected
    }

    /// Collect `.varf` / `.varfont` files, including those nested in dropped folders.
    static func collectProjectURLs(from urls: [URL]) -> [URL] {
        var collected: [URL] = []
        var seen = Set<String>()

        func ingest(_ url: URL) {
            let norm = normalizedPath(url)
            guard !seen.contains(norm) else { return }

            // Prefer extension match for direct drops — sandbox can briefly hide existence.
            if !url.hasDirectoryPath, isProjectFile(url) {
                seen.insert(norm)
                collected.append(url.standardizedFileURL)
                return
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

            if isDirectory.boolValue {
                guard let contents = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { return }
                for item in contents {
                    ingest(item)
                }
            } else if isProjectFile(url) {
                seen.insert(norm)
                collected.append(url.standardizedFileURL)
            }
        }

        for url in urls {
            ingest(url)
        }
        return collected
    }

    static func isFontFile(_ url: URL) -> Bool {
        fontFileExtensions.contains(url.pathExtension.lowercased())
    }

    static func isProjectFile(_ url: URL) -> Bool {
        ProjectFileFormat.isProjectFileURL(url)
    }

    static let fontDropTypes: [UTType] = [.fileURL, .varfontProject]

    private static let fontFileExtensions: Set<String> = ["ttf", "otf", "woff", "woff2"]
    private static let fontContentTypes: [UTType] = [
        UTType(filenameExtension: "ttf")!,
        UTType(filenameExtension: "otf")!,
        UTType(filenameExtension: "woff")!,
        UTType(filenameExtension: "woff2")!,
    ]
}
