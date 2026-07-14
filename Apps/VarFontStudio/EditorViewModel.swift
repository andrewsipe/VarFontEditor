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

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var openProjects: [OpenProject] = []
    @Published var activeProjectID: String?
    @Published var selectedInstanceKey: String?
    @Published var selectedInstanceKeys: Set<String> = []
    @Published var selectedAxisStopID: String?
    /// Review / export chrome and preflight sessions (Track B1 carve-out).
    let saveReview = SaveReviewStore()
    /// Conflict / plan-issue resolver sheets and review-queue walk (Track B2).
    let issueResolvers = IssueResolverStore()
    /// Inspector scope / reveal / axis-tree focus chrome (Track B3).
    let inspectorFocus = InspectorFocusStore()
    /// Workspace confirmations / missing-fonts / target picker (Track B4).
    let workspace = ProjectWorkspaceStore()
    @Published var showShortcutsHelp = false
    @Published var searchText = ""
    @Published private(set) var instanceSearchFocusToken: UUID?
    @Published var instanceFilter: InstanceFilter = .all
    @Published var instancePlan: InstancePlan?
    @Published private(set) var planRevision = 0
    @Published var statusMessage: String?
    @Published var isBusy = false
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

    private func applyDefaultNameIDStrategy(to document: inout ProjectDocument) {
        document.nameidStrategy = StudioAppPreferences.defaultNameIDStrategy
        document.syncNameIDStrategyToFonts()
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


    // MARK: - Inspector

    func isInstanceIncluded(_ key: String) -> Bool {
        instanceListDisplay.includedByKey[key]
            ?? instancePlan?.instances.first(where: { $0.key == key })?.included
            ?? true
    }

    func focusInspectorAxisStop(tag: String, stopID: String) {
        inspectorFocus.focusAxisTag(tag)
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
        workspace.pendingAddFontProjectID = projectID ?? activeProjectID
        let panel = NSOpenPanel()
        panel.title = "Add Font to Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.fontContentTypes
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.addFont(at: url, toProjectID: self?.workspace.pendingAddFontProjectID ?? self?.activeProjectID)
                self?.workspace.pendingAddFontProjectID = nil
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
                workspace.missingFontsRequest = MissingFontsRequest(
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
        guard var request = workspace.missingFontsRequest,
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
            self?.workspace.missingFontsRequest = request
        }
    }

    func cancelMissingFontsRequest() {
        workspace.missingFontsRequest = nil
    }

    func completeMissingFontsRequest() {
        guard let request = workspace.missingFontsRequest, request.allResolved else { return }
        var document = request.document
        for entry in request.entries {
            guard let resolvedURL = entry.resolvedURL,
                  let fontIndex = document.fonts.firstIndex(where: { $0.id == entry.fontID }) else { continue }
            document.fonts[fontIndex].sourcePath = resolvedURL.path
        }
        let projectURL = request.projectFileURL
        workspace.missingFontsRequest = nil
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
        workspace.confirmQuitRequested = true
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
        workspace.confirmQuitRequested = false
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
        workspace.confirmQuitRequested = false
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
        workspace.confirmQuitRequested = false
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
        inspectorFocus.revealProjectScope(fileNaming: fileNaming)
    }

    func clearInspectorFileNamingFocus() {
        inspectorFocus.clearFileNamingFocus()
    }

    func updateInspectorScopeForSelection() {
        inspectorFocus.updateScopeForInstanceSelection(
            hasInspectableInstance: inspectorInspectableInstance != nil
        )
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
        workspace.confirmRemoveFont = FontRemovalRequest(projectID: projectID, fontID: fontID)
    }

    func confirmRemoveFontAction() {
        guard let request = workspace.confirmRemoveFont else { return }
        workspace.confirmRemoveFont = nil
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
        workspace.projectTargetPickerMode = .moveFont(fontID: fontID, fromProjectID: fromProjectID)
    }

    func presentCombineProjectsPicker(into targetProjectID: String) {
        workspace.projectTargetPickerMode = .combineInto(targetProjectID: targetProjectID)
    }

    func cancelProjectTargetPicker() {
        workspace.projectTargetPickerMode = nil
    }

    func completeProjectTargetPicker(selectedProjectID: String) {
        guard let mode = workspace.projectTargetPickerMode else { return }
        workspace.projectTargetPickerMode = nil
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

        workspace.confirmMoveFont = FontMoveRequest(
            fontID: fontID,
            fromProjectID: fromProjectID,
            toProjectID: toProjectID
        )
    }

    func confirmMoveFontAction() {
        guard let request = workspace.confirmMoveFont else { return }
        workspace.confirmMoveFont = nil
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
        workspace.confirmSplitFont = FontSplitRequest(fontID: fontID, fromProjectID: fromProjectID)
    }

    func confirmSplitFontAction() {
        guard let request = workspace.confirmSplitFont else { return }
        workspace.confirmSplitFont = nil
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

        workspace.confirmCombineProjects = ProjectCombineRequest(
            sourceProjectID: sourceID,
            targetProjectID: targetID
        )
    }

    func confirmCombineProjectsAction() {
        guard let request = workspace.confirmCombineProjects else { return }
        workspace.confirmCombineProjects = nil
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
            workspace.confirmCloseProjectID = id
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
        guard let id = workspace.confirmCloseProjectID else { return }
        workspace.confirmCloseProjectID = nil
        closeProject(id: id, force: true)
    }

    func confirmCloseProjectSaveAction() {
        guard let projectID = workspace.confirmCloseProjectID,
              let open = openProject(for: projectID) else { return }
        if let url = open.projectFileURL {
            Task { @MainActor in
                await self.saveProject(document: open.document, to: url, projectID: projectID)
                if self.openProject(for: projectID)?.projectFileDirty == false {
                    self.workspace.confirmCloseProjectID = nil
                    self.closeProject(id: projectID, force: true)
                }
            }
        } else {
            workspace.confirmCloseProjectID = projectID
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
                    self?.workspace.confirmCloseProjectID = nil
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
            workspace.confirmCloseProjectID = id
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

    func refreshCanSave() {
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

}


extension EditorViewModel: SaveReviewHost {}

extension EditorViewModel: IssueResolverHost {}
