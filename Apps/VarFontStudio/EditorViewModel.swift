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

enum StudioFooterPanelMode: String, CaseIterable, Identifiable {
    case namingOrder
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .namingOrder: "Naming order"
        case .preview: "Preview"
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

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var openProjects: [OpenProject] = []
    @Published var activeProjectID: String?
    @Published var selectedInstanceKey: String?
    @Published var selectedInstanceKeys: Set<String> = []
    @Published var selectedAxisStopID: String?
    /// Footer chrome: Naming order (default) or live glyph Preview.
    @Published var footerPanelMode: StudioFooterPanelMode = .namingOrder
    /// Last instance hovered in Preview (sticky across row gaps).
    @Published var previewHoverInstanceKey: String?
    /// True while the pointer is over an instance row in Preview mode.
    @Published var isPreviewHoverActive = false
    /// Review / export chrome and preflight sessions (Track B1 carve-out).
    let saveReview = SaveReviewStore()
    /// Conflict / plan-issue resolver sheets and review-queue walk (Track B2).
    let issueResolvers = IssueResolverStore()
    /// Inspector scope / reveal / axis-tree focus chrome (Track B3).
    let inspectorFocus = InspectorFocusStore()
    /// Workspace confirmations / missing-fonts / target picker (Track B4).
    let workspace = ProjectWorkspaceStore()
    let fontPreviewCache = SourceFontPreviewCache()
    @Published var showShortcutsHelp = false
    @Published var searchText = ""
    @Published var instanceSearchFocusToken: UUID?
    @Published var instanceFilter: InstanceFilter = .all
    @Published var instancePlan: InstancePlan?
    @Published var planRevision = 0
    @Published var statusMessage: String?
    @Published var isBusy = false
    /// 0...1 while `isBusy`; nil means indeterminate.
    @Published var busyProgress: Double?
    @Published var busyStatus: String?
    @Published var instanceListDisplay = InstanceListDisplay.empty
    @Published var canSave = false

    /// Workspace confirmations / missing-fonts / target picker (Track B4).
    
    let workspaceDrag = WorkspaceDragCoordinator()

    var debouncedPlanTask: Task<Void, Never>?
    private var statusMessageDismissTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    let commitService = CommitService()
    var sourceBookmarks: [String: Data] = [:]

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

    func markProjectFileDirty(projectID: String? = nil) {
        guard let id = projectID ?? activeProjectID,
              let idx = openProjects.firstIndex(where: { $0.id == id }) else { return }
        guard !openProjects[idx].projectFileDirty else { return }
        openProjects[idx].projectFileDirty = true
        publishOpenProjects()
    }

    func applyDefaultNameIDStrategy(to document: inout ProjectDocument) {
        document.nameidStrategy = StudioAppPreferences.defaultNameIDStrategy
        document.syncNameIDStrategyToFonts()
    }

    /// Settings default — persists app-wide and applies to every open project/file.
    func applyAppDefaultNameIDStrategy(_ strategy: NameIDStrategy) {
        StudioAppPreferences.defaultNameIDStrategy = strategy
        for projectIndex in openProjects.indices {
            var document = openProjects[projectIndex].document
            guard document.nameidStrategy != strategy
                || document.fonts.contains(where: { $0.options.nameidStrategy != strategy }) else {
                continue
            }
            document.nameidStrategy = strategy
            document.syncNameIDStrategyToFonts()
            document.modified = Date()
            openProjects[projectIndex].document = document
            markProjectFileDirty(projectID: openProjects[projectIndex].id)
            let projectID = openProjects[projectIndex].id
            let fontIDs = document.fonts.map(\.id)
            for fontID in fontIDs {
                clearSaveReviewState(forProjectID: projectID, fontID: fontID)
            }
            for fontID in fontIDs {
                refreshCommitDiffPreview(forProjectID: projectID, fontID: fontID)
            }
        }
        if let activeID = activeProjectID,
           let document = openProjects.first(where: { $0.id == activeID })?.document {
            project = document
        }
        publishOpenProjects()
    }

    func registerSourceBookmark(url: URL, fontID: String) {
        if let bookmark = SourceFontAccess.makeBookmark(for: url) {
            sourceBookmarks[fontID] = bookmark
        }
    }

    func analyzeSourceFont(
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

    func removeSourceBookmark(fontID: String) {
        sourceBookmarks.removeValue(forKey: fontID)
        fontPreviewCache.invalidate(fontID: fontID)
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
            let previous = openProjects[idx].selectedFontID
            openProjects[idx].selectedFontID = newValue
            if previous != newValue {
                clearPreviewHover()
                if let previous {
                    fontPreviewCache.invalidate(fontID: previous)
                }
            }
            publishOpenProjects()
        }
    }

    var activeProjectIndex: Int? {
        guard let activeProjectID else { return nil }
        return openProjects.firstIndex { $0.id == activeProjectID }
    }

    var activeOpenProject: OpenProject? {
        guard let idx = activeProjectIndex else { return nil }
        return openProjects[idx]
    }

    func publishOpenProjects() {
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

    func beginBusyWork(status: String, progress: Double? = 0) {
        isBusy = true
        busyStatus = status
        busyProgress = progress
    }

    func updateBusyWork(status: String? = nil, progress: Double? = nil) {
        if let status { busyStatus = status }
        if let progress { busyProgress = min(1, max(0, progress)) }
    }

    func endBusyWork() {
        isBusy = false
        busyStatus = nil
        busyProgress = nil
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

    var undoStack: [ProjectDocument] {
        get { activeOpenProject?.undoStack ?? [] }
        set {
            guard let idx = activeProjectIndex else { return }
            openProjects[idx].undoStack = newValue
            publishOpenProjects()
        }
    }

    var redoStack: [ProjectDocument] {
        get { activeOpenProject?.redoStack ?? [] }
        set {
            guard let idx = activeProjectIndex else { return }
            openProjects[idx].redoStack = newValue
            publishOpenProjects()
        }
    }

    init() {
        saveReview.host = self
        saveReview.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        issueResolvers.host = self
        issueResolvers.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        inspectorFocus.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        workspace.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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

        // Warm vfcommit so the first Review open does not pay Python/fontTools startup.
        Task { await commitService.ensureWorkerReady() }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var selectedFont: FontDocument? {
        guard let project, let selectedFontID else { return nil }
        return project.fonts.first { $0.id == selectedFontID }
    }

    /// Instance driving the footer Preview (sticky last hover wins over selection).
    var previewActiveInstance: PlannedInstance? {
        if footerPanelMode == .preview,
           let key = previewHoverInstanceKey,
           let plan = instancePlan,
           let hovered = plan.instances.first(where: { $0.key == key }) {
            return hovered
        }
        if let selected = selectedInstance {
            return selected
        }
        return instancePlan?.instances.first
    }

    var isPreviewHoverPeeking: Bool {
        guard footerPanelMode == .preview,
              isPreviewHoverActive,
              let hover = previewHoverInstanceKey else { return false }
        return hover != selectedInstanceKey
    }

    /// - Parameter key: Pass a key on enter; leave `nil` on exit so the last hover stays sticky.
    func setPreviewHoverInstanceKey(_ key: String?, active: Bool) {
        if let key, previewHoverInstanceKey != key {
            previewHoverInstanceKey = key
        }
        if isPreviewHoverActive != active {
            isPreviewHoverActive = active
        }
    }

    func clearPreviewHover() {
        previewHoverInstanceKey = nil
        isPreviewHoverActive = false
    }

    func setFooterPanelMode(_ mode: StudioFooterPanelMode) {
        guard footerPanelMode != mode else { return }
        footerPanelMode = mode
        if mode != .preview {
            clearPreviewHover()
        }
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

        // Keep Preview pinned to the click target (don’t leave a stale sticky hover).
        if footerPanelMode == .preview, let selectedInstanceKey {
            previewHoverInstanceKey = selectedInstanceKey
            isPreviewHoverActive = false
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
}


extension EditorViewModel: SaveReviewHost {}

extension EditorViewModel: IssueResolverHost {}
