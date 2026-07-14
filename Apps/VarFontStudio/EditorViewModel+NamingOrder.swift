import Foundation
import VarFontCore

extension EditorViewModel {
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

    func refreshInstanceListDisplay() {
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
}
