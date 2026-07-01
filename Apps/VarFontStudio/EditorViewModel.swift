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
    @Published private(set) var saveReviewSessionsByKey: [String: CommitPreflightSession] = [:]
    @Published var presentCommitDiffSheet = false
    @Published private(set) var saveReviewOpenRequest: SaveReviewOpenRequest?
    @Published private(set) var saveReviewLoadingKeys: Set<String> = []
    @Published private(set) var saveReviewSelectedFontIDByProjectID: [String: String] = [:]
    @Published private(set) var saveReviewExplicitlyOpenedProjectIDs: Set<String> = []
    @Published var searchText = ""
    @Published var instanceFilter: InstanceFilter = .all
    @Published var instancePlan: InstancePlan?
    @Published private(set) var planRevision = 0
    @Published var statusMessage: String?
    @Published var isBusy = false
    @Published private(set) var instanceListDisplay = InstanceListDisplay.empty
    @Published private(set) var canSave = false

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
    /// After drop on add-to-project zone with multiple projects — pick target.
    @Published var pendingDropURLs: [URL]?
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
        guard let activeProjectID else { return "Save Review" }
        return saveReviewWindowTitle(forProjectID: activeProjectID)
    }

    func saveReviewWindowTitle(forProjectID projectID: String) -> String {
        if let open = openProject(for: projectID) {
            return "Save Review — \(projectTabLabel(for: open))"
        }
        return "Save Review"
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

    func isSaveReviewLoading(forProjectID projectID: String, fontID: String? = nil) -> Bool {
        if let fontID {
            return saveReviewLoadingKeys.contains(saveReviewSessionKey(projectID: projectID, fontID: fontID))
        }
        return saveReviewLoadingKeys.contains { $0.hasPrefix("\(projectID)|") }
    }

    func selectSaveReviewFont(projectID: String, fontID: String) {
        saveReviewSelectedFontIDByProjectID[projectID] = fontID
        if saveReviewSession(forProjectID: projectID, fontID: fontID) == nil,
           canPreviewSaveReview(forProjectID: projectID, fontID: fontID) {
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
        saveReviewOpenRequest = SaveReviewOpenRequest(projectID: targetID, token: UUID())
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
        } else {
            saveReviewSessionsByKey.removeAll()
            saveReviewLoadingKeys.removeAll()
            saveReviewSelectedFontIDByProjectID.removeAll()
            saveReviewExplicitlyOpenedProjectIDs.removeAll()
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

    private func registerSourceBookmark(url: URL, fontID: String) {
        if let bookmark = SourceFontAccess.makeBookmark(for: url) {
            sourceBookmarks[fontID] = bookmark
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
        case let (.font(fontID, fromProjectID, _), .project(targetID)):
            requestMoveFont(fontID: fontID, fromProjectID: fromProjectID, toProjectID: targetID)
        case let (.font(fontID, fromProjectID, _), .newProject):
            requestSplitFontToNewProject(fontID: fontID, fromProjectID: fromProjectID)
        case let (.project(sourceID, _), .project(targetID)):
            requestCombineProjects(sourceID: sourceID, intoTargetID: targetID)
        case (.project, .newProject):
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

    /// Full naming order filtered to axes that participate in instance naming plus clarifier tokens.
    var namingChainInstanceTags: [String] {
        namingChainTags.filter { NamingToken.isClarifier($0) || axisParticipatesInInstanceGrid(tag: $0) }
    }

    /// Tags shown in the chain footer; STAT-only axes and empty clarifiers are hidden when requested.
    func visibleNamingChainTags(hideStatOnly: Bool) -> [String] {
        let base = hideStatOnly ? namingChainInstanceTags : namingChainTags
        guard let fontID = selectedFontID else { return base }
        return base.filter { tag in
            if NamingToken.isClarifier(tag) {
                return clarifierHasValue(for: tag, fontID: fontID)
            }
            return true
        }
    }

    func clarifierHasValue(for token: String, fontID: String) -> Bool {
        guard let category = NamingToken.clarifierCategory(for: token) else { return false }
        return fileRole(for: fontID)?.label(for: category) != nil
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
        return project?.naming.elidedFallback ?? "Regular"
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
        conflictResolverRequest = AxisConflictResolverSession(bundle: bundle)
        focusConflictAxis(bundle)
    }

    func presentFirstConflictResolver() {
        guard let first = axisConflictBundles.first else { return }
        presentConflictResolver(bundle: first)
    }

    func dismissConflictResolver() {
        conflictResolverRequest = nil
    }

    func applyConflictFix(_ action: ConflictFixAction, axisTag: String) {
        guard var project, let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return
        }
        pushUndoSnapshot()
        ConflictResolver.apply(action, axisTag: axisTag, to: &project.fonts[fontIndex])
        project.fonts[fontIndex].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        conflictResolverRequest = nil
        regeneratePlan()
        if let sameAxis = axisConflictBundles.first(where: { $0.axisTag == axisTag }) {
            presentConflictResolver(bundle: sameAxis)
        } else if let next = axisConflictBundles.first {
            presentConflictResolver(bundle: next)
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
                    field: "AxisValue",
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
                field: "subfamilyNameID",
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

    func showDuplicateInstances(matching instance: PlannedInstance) {
        instanceFilter = .duplicates
        searchText = instance.composedName
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
            let analysis = try FontAnalysisReader.analyze(url: url)
            try validateVariableFont(analysis)
            let imported = ProjectImporter.newProject(from: analysis, sourceURL: url)
            if let fontID = imported.fonts.first?.id {
                registerSourceBookmark(url: url, fontID: fontID)
            }
            let open = OpenProject(document: imported, selectedFontID: imported.fonts.first?.id)
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

    func addFont(at url: URL, toProjectID: String? = nil) async {
        let targetID = toProjectID ?? activeProjectID
        if openProjects.isEmpty {
            await createProject(from: url)
            return
        }
        guard let targetID,
              openProjects.contains(where: { $0.id == targetID }) else {
            postStatusMessage("No project selected")
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
            let analysis = try FontAnalysisReader.analyze(url: url)
            try validateVariableFont(analysis)
            guard let idx = openProjects.firstIndex(where: { $0.id == targetID }) else { return }
            ProjectImporter.addFont(analysis, sourceURL: url, to: &openProjects[idx].document)
            let newFontID = openProjects[idx].document.fonts.last?.id
            if let newFontID {
                registerSourceBookmark(url: url, fontID: newFontID)
            }
            activateProject(id: targetID)
            if let newFontID {
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

    func renameProject(id: String, displayName: String) {
        guard let idx = openProjects.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        openProjects[idx].document.displayName = trimmed.isEmpty ? nil : trimmed
        openProjects[idx].document.modified = Date()
        publishOpenProjects()
    }

    func projectTabLabel(for openProject: OpenProject) -> String {
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
        return "\(font.axes.filter { $0.role == .instance }.map(\.values.count).reduce(1, *))"
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
        openProjects[pIdx].document.fonts.removeAll { $0.id == fontID }
        removeSourceBookmark(fontID: fontID)

        if openProjects[pIdx].document.fonts.isEmpty {
            closeProject(id: projectID, force: true)
            postStatusMessage("Project closed — no files remaining")
            return
        }

        if openProjects[pIdx].selectedFontID == fontID {
            openProjects[pIdx].selectedFontID = openProjects[pIdx].document.fonts.first?.id
        }

        activateProject(id: projectID)
        publishOpenProjects()
        refreshCanSave()
        regeneratePlan()
        postStatusMessage("Removed font from project")
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

        let newOpen = OpenProject(document: newDocument, selectedFontID: font.id)
        openProjects.append(newOpen)

        if openProjects[fromIdx].selectedFontID == fontID {
            openProjects[fromIdx].selectedFontID = openProjects[fromIdx].document.fonts.first?.id
        }
        openProjects[fromIdx].document.modified = Date()

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
        confirmCloseProjectID = id
    }

    func confirmCloseProjectAction() {
        guard let id = confirmCloseProjectID else { return }
        confirmCloseProjectID = nil
        closeProject(id: id, force: true)
    }

    func closeProject(id: String, force: Bool) {
        guard let idx = openProjects.firstIndex(where: { $0.id == id }) else { return }
        if !force, openProjects[idx].document.fonts.contains(where: \.dirty) {
            confirmCloseProjectID = id
            return
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
            return "Remove this project from the workspace?"
        }
        let name = projectTabLabel(for: project)
        if project.document.fonts.contains(where: \.dirty) {
            return "Remove \(name)? One or more files have unsaved changes."
        }
        return "Remove \(name) from the workspace?"
    }

    private func fontDocument(fontID: String, projectID: String) -> FontDocument? {
        openProjects.first(where: { $0.id == projectID })?
            .document.fonts.first(where: { $0.id == fontID })
    }

    func importDroppedFonts(_ urls: [URL], disposition: FontDropDisposition) async {
        let valid = urls.filter { Self.isFontFile($0) }
        guard !valid.isEmpty else {
            postStatusMessage("No supported font files (.ttf, .otf, .woff, .woff2)")
            return
        }

        switch disposition {
        case .createNewProject:
            for url in valid {
                await createProject(from: url)
            }
        case .addToProject:
            if openProjects.count == 1, let onlyID = openProjects.first?.id {
                for url in valid {
                    await addFont(at: url, toProjectID: onlyID)
                }
            } else {
                pendingDropURLs = valid
            }
        }
    }

    func completePendingDrop(addToProjectID: String) async {
        guard let urls = pendingDropURLs else { return }
        pendingDropURLs = nil
        for url in urls {
            await addFont(at: url, toProjectID: addToProjectID)
        }
    }

    func cancelPendingDrop() {
        pendingDropURLs = nil
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

    /// Clarifiers are per-file naming tokens. Editable on variants and on the sole file in a project;
    /// read-only on the master when multiple files share a project (variants carry clarifiers).
    var areFileClarifiersEditable: Bool {
        guard let selectedFontID else { return false }
        return areFileClarifiersEditable(for: selectedFontID)
    }

    func areFileClarifiersEditable(for fontID: String) -> Bool {
        let isMaster = fileRole(for: fontID)?.kind == .master
        return !isMaster || !projectHasMultipleFiles
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
        for index in project.fonts.indices {
            if project.fonts[index].id == fontID {
                project.fonts[index].fileRole = .master()
            } else {
                var role = project.fonts[index].fileRole ?? .variant(masterFontID: fontID)
                role.kind = .variant
                role.masterFontID = fontID
                project.fonts[index].fileRole = role
            }
            project.fonts[index].dirty = true
        }
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateFont(id: fontID) { font in
            font.options.familyPSPrefix = trimmed.isEmpty ? nil : trimmed
        }
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
        guard let font = selectedFont, let projectID = activeProjectID else { return }
        let analysis = try? FontAnalysisReader.analyze(url: URL(fileURLWithPath: font.sourcePath))
        let inferred = FileClarifierInference.infer(
            sourceURL: URL(fileURLWithPath: font.sourcePath),
            analysis: analysis,
            font: font
        )
        pushUndoSnapshot()
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == font.id }) else { return }
        var role = project.fonts[index].fileRole ?? .variant(masterFontID: masterFontID(for: projectID) ?? "")
        let isMultiFileMaster = role.kind == .master && project.fonts.count > 1
        if isMultiFileMaster {
            // Clarifiers belong on variant files — master keeps axis tree only.
            role.clarifiers = []
            role.elidedFallbackOverride = nil
        } else {
            role.clarifiers = inferred.clarifiers
            role.elidedFallbackOverride = inferred.elidedFallbackOverride
        }
        if project.fonts[index].options.familyPSPrefix?.isEmpty != false,
           let prefix = analysis?.source.familyPSPrefix, !prefix.isEmpty {
            project.fonts[index].options.familyPSPrefix = prefix
        }
        project.fonts[index].fileRole = role
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func pushMasterAxisTreeToAllFonts() {
        guard let project, let projectID = activeProjectID,
              let masterID = masterFontID(for: projectID),
              let masterFont = project.fonts.first(where: { $0.id == masterID }) else { return }
        pushUndoSnapshot()
        guard var updated = self.project else { return }
        for index in updated.fonts.indices where updated.fonts[index].id != masterID {
            updated.fonts[index].axes = mergeAxesFromMaster(
                master: masterFont.axes,
                into: updated.fonts[index].axes,
                syncRoles: updated.template.syncRoles
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

    private func mergeAxesFromMaster(
        master: [AxisDefinition],
        into target: [AxisDefinition],
        syncRoles: Bool
    ) -> [AxisDefinition] {
        let targetByTag = Dictionary(uniqueKeysWithValues: target.map { ($0.tag, $0) })
        var merged: [AxisDefinition] = []
        for masterAxis in master {
            if var existing = targetByTag[masterAxis.tag] {
                existing.displayName = masterAxis.displayName
                existing.values = masterAxis.values.map { stop in
                    var copy = stop
                    copy.id = "\(masterAxis.tag)-\(UUID().uuidString.prefix(8))"
                    return copy
                }
                if syncRoles {
                    existing.role = masterAxis.role
                }
                merged.append(existing)
            } else {
                var imported = masterAxis
                imported.values = imported.values.map { stop in
                    var copy = stop
                    copy.id = "\(masterAxis.tag)-\(UUID().uuidString.prefix(8))"
                    return copy
                }
                merged.append(imported)
            }
        }
        for axis in target where !master.contains(where: { $0.tag == axis.tag }) {
            merged.append(axis)
        }
        return merged
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
            font.axes[axisIndex].values[stopIndex].value = clamped
            font.axes[axisIndex].values.sort { $0.value < $1.value }
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
        refreshCanSave()
        regeneratePlan()
    }

    func redo() {
        guard let current = project, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        project = next
        canSave = next.fonts.contains(where: \.dirty)
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

    func insertAxisStop(axisTag: String, value: Double, name: String) {
        var addedStopID: String?
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            let stopID = "\(axisTag)-\(UUID().uuidString.prefix(8))"
            let stop = AxisValue(
                id: stopID,
                value: value,
                name: name,
                elidable: false,
                statFormat: 1
            )
            font.axes[axisIndex].values.append(stop)
            font.axes[axisIndex].values.sort { $0.value < $1.value }
            addedStopID = stopID
        }
        selectedAxisStopID = addedStopID
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

        let sourceURL = URL(fileURLWithPath: project.fonts[fontIndex].sourcePath)
        guard let analysis = try? FontAnalysisReader.analyze(url: sourceURL) else { return }

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

    /// Write to `font.outputPath` when set; otherwise open Save Review (same as Save Copy).
    func save() {
        guard canSave else {
            postStatusMessage("Nothing to save — make an edit first.")
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

        if let outputURL = rememberedOutputURL(forProjectID: projectID, fontID: fontID) {
            guard let session = await ensureSaveReviewSession(projectID: projectID, fontID: fontID) else { return }
            guard session.preflight.ok else {
                postStatusMessage(session.preflight.errors.first?.message ?? "Save preview failed.")
                return
            }
            await performSave(session: session, to: outputURL)
            return
        }

        saveCopy()
    }

    @MainActor
    func ensureSaveReviewSession(projectID: String, fontID: String) async -> CommitPreflightSession? {
        if let session = saveReviewSession(forProjectID: projectID, fontID: fontID),
           session.preflight.ok {
            return session
        }
        return await refreshCommitDiffPreviewAsync(forProjectID: projectID, fontID: fontID)
    }

    @discardableResult
    @MainActor
    func refreshCommitDiffPreviewAsync(
        forProjectID projectID: String? = nil,
        fontID: String? = nil,
        presentSheet: Bool = false
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
            dryRun: true
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
            let result = try await commitService.commit(dryRunRequest)
            if result.ok {
                let diffReport = CommitDiffBuilder.build(
                    analysis: analysis,
                    font: font,
                    plan: plan,
                    result: result
                )
                var writeRequest = CommitRequestBuilder.make(
                    font: font,
                    naming: projectDoc.naming,
                    plan: plan,
                    outputPath: outputPath,
                    dryRun: false
                )
                writeRequest.sourcePath = helperSourcePath
                let session = CommitPreflightSession(
                    projectID: targetProjectID,
                    fontID: font.id,
                    dryRunRequest: dryRunRequest,
                    baseRequest: writeRequest,
                    preflight: result,
                    diffReport: diffReport
                )
                saveReviewSessionsByKey[sessionKey] = session
                if presentSheet {
                    presentCommitDiffSheet = true
                }
                return session
            }
            let message = result.errors.first?.message ?? "Save preview failed."
            postStatusMessage(message)
            return nil
        } catch {
            postStatusMessage(commitFailureMessage(error))
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
            postStatusMessage("Exported commit JSON to \(directory.lastPathComponent)")
        } catch {
            postStatusMessage("JSON export failed: \(error.localizedDescription)")
        }
    }

    func presentSavePanel(for session: CommitPreflightSession) {
        guard let font = font(forProjectID: session.projectID, fontID: session.fontID) else { return }

        let panel = NSSavePanel()
        panel.title = "Save Patched Font Copy"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = URL(fileURLWithPath: session.baseRequest.outputPath).lastPathComponent
        let sourceURL = URL(fileURLWithPath: font.sourcePath)
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        let ext = sourceURL.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [type]
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
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
            postStatusMessage(session.preflight.errors.first?.message ?? "Save preview failed.")
            return
        }

        if usingRememberedPath, let url = rememberedOutputURL(forProjectID: session.projectID, fontID: session.fontID) {
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
            postStatusMessage("Nothing to save.")
            return
        }

        for font in targets {
            guard let plan = instancePlan(forProjectID: projectID, fontID: font.id) else {
                postStatusMessage("Cannot save \(fontBasename(for: font)) — planning failed.")
                return
            }
            if plan.instances.contains(where: { $0.included && $0.duplicate }) {
                postStatusMessage("Resolve duplicate instance names in \(fontBasename(for: font)) before saving.")
                return
            }
        }

        var sessions: [String: CommitPreflightSession] = [:]
        for font in targets {
            guard let session = await ensureSaveReviewSession(projectID: projectID, fontID: font.id) else {
                postStatusMessage("Save preview failed for \(fontBasename(for: font)).")
                return
            }
            guard session.preflight.ok else {
                postStatusMessage(session.preflight.errors.first?.message ?? "Save preview failed.")
                return
            }
            sessions[font.id] = session
        }

        var outputURLs: [String: URL] = [:]
        for font in targets {
            if let url = rememberedOutputURL(forProjectID: projectID, fontID: font.id) {
                outputURLs[font.id] = url
            }
        }

        var outputDirectory: URL?
        if targets.contains(where: { outputURLs[$0.id] == nil }) {
            guard let directory = await chooseOutputDirectory(
                title: "Save All Files",
                message: "Choose a folder for patched font copies."
            ) else { return }
            outputDirectory = directory
            for font in targets where outputURLs[font.id] == nil {
                let suggested = CommitRequestBuilder.suggestedOutputPath(for: font.sourcePath)
                let name = URL(fileURLWithPath: suggested).lastPathComponent
                outputURLs[font.id] = directory.appendingPathComponent(name)
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
        postStatusMessage("Saved \(targets.count) files to \(folderLabel)")
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

    func performSave(session: CommitPreflightSession, to outputURL: URL, manageBusyState: Bool = true) async {
        guard let projectIndex = openProjects.firstIndex(where: { $0.id == session.projectID }),
              let fontIndex = openProjects[projectIndex].document.fonts.firstIndex(where: { $0.id == session.fontID }) else {
            return
        }

        var request = session.baseRequest
        request.outputPath = outputURL.path
        request.dryRun = false
        request.requestID = UUID().uuidString.lowercased()

        if manageBusyState { isBusy = true }
        defer { if manageBusyState { isBusy = false } }

        do {
            let result = try await commitService.commit(request)
            guard result.ok else {
                let message = result.errors.first?.message ?? "Save failed."
                postStatusMessage(message)
                return
            }

            var project = openProjects[projectIndex].document
            project.fonts[fontIndex].outputPath = outputURL.path
            project.fonts[fontIndex].dirty = false
            openProjects[projectIndex].document = project
            publishOpenProjects()
            if activeProjectID == session.projectID {
                self.project = project
                refreshCanSave()
            }
            clearSaveReviewState(forProjectID: session.projectID, fontID: session.fontID)
            presentCommitDiffSheet = false

            if let count = result.summary?.instancesWritten {
                postStatusMessage("Saved \(count) instances to \(outputURL.lastPathComponent)")
            } else {
                postStatusMessage("Saved \(outputURL.lastPathComponent)")
            }
        } catch {
            postStatusMessage(commitFailureMessage(error))
        }
    }

    private func commitFailureMessage(_ error: Error) -> String {
        switch error {
        case CommitServiceError.helperNotFound:
            "Save helper not found — vfcommit.py is missing from Tools/vfcommit."
        case let CommitServiceError.helperUnavailable(path):
            "Save helper unavailable at \(path)."
        case let CommitServiceError.helperFailed(detail):
            "Save helper failed: \(detail)"
        case let CommitServiceError.invalidHelperOutput(detail):
            if detail.localizedCaseInsensitiveContains("fonttools")
                || detail.localizedCaseInsensitiveContains("fontTools")
            {
                "Save helper needs fontTools for Python 3 — run: pip3 install fonttools. (\(detail))"
            } else {
                "Save helper returned invalid output: \(detail)"
            }
        default:
            "Save failed: \(error.localizedDescription)"
        }
    }

    func importDroppedFonts(_ urls: [URL]) async {
        if openProjects.isEmpty {
            for url in urls.filter({ Self.isFontFile($0) }) {
                await createProject(from: url)
            }
            return
        }
        // Default legacy path: add to active project (split overlay uses disposition API).
        for url in urls.filter({ Self.isFontFile($0) }) {
            await addFont(at: url, toProjectID: activeProjectID)
        }
    }

    static func isFontFile(_ url: URL) -> Bool {
        fontFileExtensions.contains(url.pathExtension.lowercased())
    }

    static let fontDropTypes: [UTType] = [.fileURL]

    private static let fontFileExtensions: Set<String> = ["ttf", "otf", "woff", "woff2"]
    private static let fontContentTypes: [UTType] = [
        UTType(filenameExtension: "ttf")!,
        UTType(filenameExtension: "otf")!,
        UTType(filenameExtension: "woff")!,
        UTType(filenameExtension: "woff2")!,
    ]
}
