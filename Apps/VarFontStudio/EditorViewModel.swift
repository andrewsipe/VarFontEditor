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

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var openProjects: [OpenProject] = []
    @Published var activeProjectID: String?
    @Published var selectedInstanceKey: String?
    @Published var selectedInstanceKeys: Set<String> = []
    @Published var selectedAxisStopID: String?
    /// Axis tag to expand when inspector navigates to a stop.
    @Published var inspectorFocusedAxisTag: String?
    /// Inspector bottom warnings drawer — expanded shows full conflict detail.
    @Published var inspectorWarningsDrawerExpanded = false
    @Published var searchText = ""
    @Published var instanceFilter: InstanceFilter = .all
    @Published var instancePlan: InstancePlan?
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

    /// Active project document (compatibility shim for existing panel code).
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
        openProjects = openProjects
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

    /// Full naming order filtered to axes that participate in instance naming.
    var namingChainInstanceTags: [String] {
        namingChainTags.filter { axisParticipatesInInstanceGrid(tag: $0) }
    }

    /// Tags shown in the chain footer; STAT-only axes are hidden when requested.
    func visibleNamingChainTags(hideStatOnly: Bool) -> [String] {
        hideStatOnly ? namingChainInstanceTags : namingChainTags
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

        let visibleTags = namingChainInstanceTags
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
        if let name = selectedFont?.axes.first(where: { $0.tag == tag })?.displayName, !name.isEmpty {
            return name
        }
        return tag
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
        let ordered = projectOrder.filter { axisTags.contains($0) }
        let remainder = axisTags.filter { !ordered.contains($0) }
        return ordered + remainder
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

    func warnings(for instance: PlannedInstance) -> [PlanWarning] {
        guard let instancePlan else { return [] }
        let chainTags = Set(instance.namingChain.map(\.tag))

        return instancePlan.warnings.filter { warning in
            switch warning.code {
            case "duplicate_composed_name":
                guard let keys = warning.keys else { return instance.duplicate }
                return keys.contains(instance.key)
            case "multiple_elidable", "empty_instance_axis":
                guard let axis = warning.axis else { return false }
                return chainTags.contains(axis)
            default:
                if let keys = warning.keys {
                    return keys.contains(instance.key)
                }
                return false
            }
        }
    }

    func inspectorConflictCount(for instance: PlannedInstance) -> Int {
        let planWarnings = warnings(for: instance)
        if !planWarnings.isEmpty { return planWarnings.count }
        return instance.duplicate ? 1 : 0
    }

    func revealInspectorWarnings(selecting key: String? = nil) {
        if let key {
            selectInstance(key: key, extend: false)
        }
        inspectorWarningsDrawerExpanded = true
    }

    func toggleInspectorWarningsDrawer() {
        inspectorWarningsDrawerExpanded.toggle()
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

    var axisPlanWarnings: [PlanWarning] {
        guard let instancePlan else { return [] }
        let axisCodes: Set<String> = ["multiple_elidable", "empty_instance_axis"]
        return instancePlan.warnings.filter { axisCodes.contains($0.code) }
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
        updateAxisRole(tag: tag, role: enabled ? .instance : .statOnly)
    }

    func setAxisStatOnly(tag: String, statOnly: Bool) {
        setAxisInstanceGridEnabled(tag: tag, enabled: !statOnly)
    }

    func axisParticipatesInInstanceGrid(tag: String) -> Bool {
        selectedFont?.axes.first(where: { $0.tag == tag })?.role == .instance
    }

    func updateAxisRole(tag: String, role: AxisRole) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == tag }) else { return }
            font.axes[axisIndex].role = role
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

    func addAxisStop(axisTag: String) {
        var addedStopID: String?
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            let axis = font.axes[axisIndex]
            let value = suggestedNewStopValue(for: axis)
            let stopID = "\(axisTag)-\(UUID().uuidString.prefix(8))"
            let stop = AxisValue(
                id: stopID,
                value: value,
                name: "New Stop",
                elidable: false,
                statFormat: 1
            )
            font.axes[axisIndex].values.append(stop)
            font.axes[axisIndex].values.sort { $0.value < $1.value }
            addedStopID = stopID
        }
        selectedAxisStopID = addedStopID
    }

    private func suggestedNewStopValue(for axis: AxisDefinition) -> Double {
        if let max = axis.max, let min = axis.min {
            if let last = axis.values.map(\.value).max() {
                return Swift.min(last + 1, max)
            }
            return axis.default ?? min
        }
        if let last = axis.values.last?.value {
            return last + 1
        }
        return axis.default ?? 0
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
        self.project = project
        canSave = true
        if debouncePlan {
            scheduleDebouncedPlanRegeneration()
        } else {
            debouncedPlanTask?.cancel()
            regeneratePlan()
        }
    }

    private func backfillMissingInferredAxisRoles() {
        guard var project,
              let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else { return }
        guard project.fonts[fontIndex].axes.contains(where: { $0.roleInferred == nil }) else { return }

        let sourceURL = URL(fileURLWithPath: project.fonts[fontIndex].sourcePath)
        guard let analysis = try? FontAnalysisReader.analyze(url: sourceURL) else { return }

        var changed = false
        for axisIndex in project.fonts[fontIndex].axes.indices {
            guard project.fonts[fontIndex].axes[axisIndex].roleInferred == nil else { continue }
            let tag = project.fonts[fontIndex].axes[axisIndex].tag
            guard let analyzed = analysis.axes.first(where: { $0.tag == tag }) else { continue }
            project.fonts[fontIndex].axes[axisIndex].roleInferred = analyzed.roleInferred
            changed = true
        }
        if changed {
            self.project = project
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
        postStatusMessage("Save is not wired yet — vfcommit helper coming next.")
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
