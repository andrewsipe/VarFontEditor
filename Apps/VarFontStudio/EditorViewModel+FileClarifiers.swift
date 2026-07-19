import Foundation
import UniformTypeIdentifiers
import VarFontCore

extension EditorViewModel {
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
        workspace.confirmSetAsMasterFontID = fontID
    }

    func confirmSetAsMasterAction() {
        guard let fontID = workspace.confirmSetAsMasterFontID else { return }
        workspace.confirmSetAsMasterFontID = nil
        setFontAsMaster(fontID: fontID)
    }

    func requestPushMasterAxisTree() {
        workspace.confirmPushAxisTree = true
    }

    func confirmPushAxisTreeAction() {
        workspace.confirmPushAxisTree = false
        pushMasterAxisTreeToAllFonts()
    }

    func dismissPersistentSaveError() {
        saveReview.setPersistentError(nil)
    }

    func postSaveFailure(_ message: String) {
        saveReview.setPersistentError(message)
        postStatusMessage(message)
    }

    func promoteFirstFontToMaster(projectIndex: Int) {
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
        let existingCode = role.code(for: category)
        role.clarifiers.removeAll { $0.category == category }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty || existingCode != nil {
            role.clarifiers.append(FileClarifier(category: category, label: trimmed, code: existingCode))
        }
        // Codes alone must not demote a multi-file master into a variant.
        project.fonts[index].fileRole = role
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func setFileClarifierCode(category: FileClarifierCategory, code: String, for fontID: String) {
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == fontID }) else { return }
        pushUndoSnapshot()

        let isMaster = project.fonts[index].fileRole?.kind == .master
            || masterFontID(for: activeProjectID ?? "") == fontID
        var role = project.fonts[index].fileRole
            ?? (isMaster ? .master() : .variant(masterFontID: masterFontID(for: activeProjectID ?? "") ?? ""))

        let existingLabel = role.label(for: category) ?? ""
        let sanitized = InstanceCodeBuilder.sanitize(code)
        role.clarifiers.removeAll { $0.category == category }
        if !existingLabel.isEmpty || sanitized != nil {
            role.clarifiers.append(
                FileClarifier(category: category, label: existingLabel, code: sanitized)
            )
        }
        // Keep master kind even when storing code-only clarifier entries.
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

    /// Whether a registration template tag can be added (no duplicate axis on the selected font).
    func canAddRegistrationTemplate(_ kind: RegistrationAxisFactory.TemplateKind) -> Bool {
        guard let axes = selectedFont?.axes else { return false }
        return RegistrationAxisFactory.addAvailability(for: kind, axes: axes) == .available
    }

    func namingAxisBlockReason(for kind: RegistrationAxisFactory.TemplateKind) -> String? {
        guard let axes = selectedFont?.axes else { return nil }
        return RegistrationAxisFactory.blockReasonCopy(
            RegistrationAxisFactory.addAvailability(for: kind, axes: axes)
        )
    }

    /// Where a newly appended naming-order tag would land, e.g. "after Weight".
    func namingOrderInsertHint(forNewTag tag: String) -> String {
        guard let project else { return "at the end of naming order" }
        let order = NamingPolicy.mergedOrder(
            projectOrder: project.naming.order,
            axisTags: (selectedFont?.axes.map(\.tag) ?? []) + [tag]
        )
        guard let index = order.firstIndex(of: tag), index > 0 else {
            return "at the start of naming order"
        }
        let previous = order[..<index].reversed().first { token in
            !NamingToken.isSpecialToken(token)
        }
        if let previous {
            let label = selectedFont?.axes.first(where: { $0.tag == previous })?.displayName
                ?? previous
            return "after \(label)"
        }
        return "at the end of naming order"
    }

    @discardableResult
    func addRegistrationTemplate(
        _ kind: RegistrationAxisFactory.TemplateKind,
        displayName: String? = nil,
        value: Double? = nil,
        code: String? = nil,
        italicOverride: Bool? = nil
    ) -> Bool {
        guard var project, let selectedFontID,
              let axes = selectedFont?.axes,
              RegistrationAxisFactory.addAvailability(for: kind, axes: axes) == .available else {
            return false
        }
        let axis: AxisDefinition
        switch kind {
        case .slope:
            axis = RegistrationAxisFactory.makeTemplateAxis(kind: .slope)
        case .width, .optical:
            let tag = kind.defaultTag
            let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false) ? name! : kind.displayName
            let resolvedValue = value ?? (kind == .width ? 100 : 12)
            axis = RegistrationAxisFactory.makeNamedStopAxis(
                tag: tag,
                displayName: resolvedName,
                stopName: resolvedName,
                value: resolvedValue,
                elidable: false,
                code: code
            )
        }
        pushUndoSnapshot()
        let changed = RegistrationAxisFactory.insertNamingAxis(
            axis,
            into: &project,
            selectedFontID: selectedFontID,
            italicOverride: kind == .slope ? italicOverride : nil
        )
        guard changed else { return false }
        self.project = project
        canSave = true
        regeneratePlan()
        return true
    }

    /// Add a custom registration axis (tag + display name). Returns false on collision / invalid tag.
    @discardableResult
    func addRegistrationAxis(
        tag: String,
        displayName: String,
        value: Double = 0,
        elidable: Bool = true,
        code: String? = nil
    ) -> Bool {
        guard var project, let selectedFontID else { return false }
        let normalized = RegistrationAxisFactory.sanitizeAxisTag(tag)
        guard !normalized.isEmpty,
              !RegistrationAxisFactory.tagExistsInFamily(tag: normalized, fonts: project.fonts) else {
            return false
        }
        let axis = RegistrationAxisFactory.makeCustomAxis(
            tag: normalized,
            displayName: displayName,
            value: value,
            elidable: elidable,
            code: code
        )
        pushUndoSnapshot()
        let changed = RegistrationAxisFactory.insertNamingAxis(
            axis,
            into: &project,
            selectedFontID: selectedFontID
        )
        guard changed else { return false }
        self.project = project
        canSave = true
        regeneratePlan()
        return true
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
        guard let font = selectedFont, var project else { return }

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

        let inferred = FileClarifierInference.infer(
            sourceURL: URL(fileURLWithPath: font.sourcePath),
            analysis: analysis,
            font: font
        )

        var didChange = false
        pushUndoSnapshot()

        if prefixWouldUpdate, let prefix = inferredPrefix, !prefix.isEmpty,
           let index = project.fonts.firstIndex(where: { $0.id == font.id }) {
            project.fonts[index].options.familyPSPrefix = prefix
            project.fonts[index].dirty = true
            didChange = true
        }

        for clarifier in inferred.clarifiers {
            switch clarifier.category {
            case .slope:
                if RegistrationAxisFactory.templateTag(for: .slope, axes: project.fonts.first?.axes ?? []) != nil {
                    for index in project.fonts.indices where !project.fonts[index].axes.contains(where: { $0.tag == "ital" }) {
                        let italic = RegistrationAxisSupport.isItalicFile(font: project.fonts[index])
                        project.fonts[index].axes.append(
                            RegistrationAxisFactory.makeItalAxis(isItalicFile: italic)
                        )
                        project.fonts[index].dirty = true
                    }
                    if !project.naming.order.contains("ital") {
                        project.naming.order.append("ital")
                    }
                    didChange = true
                }
                if let index = project.fonts.firstIndex(where: { $0.id == font.id }),
                   let axis = project.fonts[index].axes.first(where: { $0.tag == "ital" && $0.isDesignRecordOnly }),
                   let stop = axis.values.first {
                    project.fonts[index].fileStatRegistration["ital"] = stop.value
                    project.fonts[index].dirty = true
                    didChange = true
                }
            case .width, .optical, .custom:
                break
            }
        }

        if let override = inferred.elidedFallbackOverride,
           let index = project.fonts.firstIndex(where: { $0.id == font.id }) {
            var role = project.fonts[index].fileRole ?? .master()
            role.elidedFallbackOverride = override
            project.fonts[index].fileRole = role
            project.fonts[index].dirty = true
            didChange = true
        }

        project.naming.order = project.naming.order.filter { !NamingToken.isClarifier($0) }
        project.naming.order = NamingPolicy.ensurePostscriptHyphen(in: project.naming.order)

        if !didChange && !prefixWouldUpdate {
            postStatusMessage("No registration naming inferred for this file.")
            return
        }

        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
        if prefixWouldUpdate && inferred.clarifiers.isEmpty {
            postStatusMessage("Updated PostScript prefix from font metadata.")
        } else {
            postStatusMessage("Inferred registration naming from filename.")
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

    func mutateFont(id fontID: String, _ mutate: (inout FontDocument) -> Void) {
        guard var project, let index = project.fonts.firstIndex(where: { $0.id == fontID }) else { return }
        pushUndoSnapshot()
        mutate(&project.fonts[index])
        project.fonts[index].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
    }

    func normalizedProjectNaming(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applySharedFamilyPSPrefix(_ prefix: String?, to document: inout ProjectDocument) {
        for index in document.fonts.indices {
            document.fonts[index].options.familyPSPrefix = prefix
            document.fonts[index].dirty = true
        }
    }

    func syncProjectDisplayNameAndPrefix(_ name: String?, on document: inout ProjectDocument) {
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

    func updateAxisStopCode(axisTag: String, stopID: String, code: String) {
        mutateSelectedFont { font in
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            font.axes[axisIndex].values[stopIndex].code = InstanceCodeBuilder.sanitize(code)
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
            // Preserve the user's ascending/descending preference when possible.
            let preferAscending = Self.axisStopsValueSortAscending(font.axes[axisIndex].values) ?? true
            font.axes[axisIndex].values[stopIndex].value = clamped
            font.axes[axisIndex].values.sort {
                preferAscending ? $0.value < $1.value : $0.value > $1.value
            }
            if wasRegistered {
                font.fileStatRegistration[axisTag] = clamped
            }
        }
    }

    /// `true` when values are non-decreasing, `false` when non-increasing, else `nil`.
    static func axisStopsValueSortAscending(_ values: [AxisValue]) -> Bool? {
        guard values.count >= 2 else { return nil }
        let ascending = zip(values, values.dropFirst()).allSatisfy { $0.value <= $1.value }
        let descending = zip(values, values.dropFirst()).allSatisfy { $0.value >= $1.value }
        if ascending && descending { return true }
        if ascending { return true }
        if descending { return false }
        return nil
    }

    /// Toggles stop order between ascending and descending by value.
    /// Instance planner products over this array order, so the Instance list follows.
    func toggleAxisStopsValueSort(axisTag: String) {
        guard var project,
              let fontIndex = project.fonts.firstIndex(where: { $0.id == selectedFontID }),
              let axisIndex = project.fonts[fontIndex].axes.firstIndex(where: { $0.tag == axisTag }) else {
            return
        }
        let values = project.fonts[fontIndex].axes[axisIndex].values
        guard values.count >= 2 else { return }
        let ascending = Self.axisStopsValueSortAscending(values) ?? true
        let nextAscending = !ascending
        let sorted = values.sorted {
            nextAscending ? $0.value < $1.value : $0.value > $1.value
        }
        guard sorted.map(\.id) != values.map(\.id) else { return }

        pushUndoSnapshot()
        project.fonts[fontIndex].axes[axisIndex].values = sorted
        project.fonts[fontIndex].dirty = true
        project.modified = Date()
        self.project = project
        canSave = true
        regeneratePlan()
        if let projectID = activeProjectID {
            resortIncludedInstanceKeys(forProjectID: projectID)
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

    func nameidStrategy(forProjectID projectID: String, fontID: String? = nil) -> NameIDStrategy {
        guard let open = openProjects.first(where: { $0.id == projectID }) else {
            return StudioAppPreferences.defaultNameIDStrategy
        }
        if let fontID,
           let font = open.document.fonts.first(where: { $0.id == fontID }) {
            return font.options.nameidStrategy
        }
        return open.document.nameidStrategy
    }

    /// Review / export override for one file only — does not change Settings or other files.
    func setNameIDStrategy(
        forProjectID projectID: String,
        fontID: String,
        strategy: NameIDStrategy
    ) {
        guard let projectIndex = openProjects.firstIndex(where: { $0.id == projectID }),
              let fontIndex = openProjects[projectIndex].document.fonts.firstIndex(where: { $0.id == fontID })
        else { return }
        guard openProjects[projectIndex].document.fonts[fontIndex].options.nameidStrategy != strategy else {
            return
        }
        openProjects[projectIndex].document.fonts[fontIndex].options.nameidStrategy = strategy
        openProjects[projectIndex].document.fonts[fontIndex].dirty = true
        openProjects[projectIndex].document.modified = Date()
        if activeProjectID == projectID {
            project = openProjects[projectIndex].document
        }
        markProjectFileDirty(projectID: projectID)
        publishOpenProjects()
        clearSaveReviewState(forProjectID: projectID, fontID: fontID)
        refreshCommitDiffPreview(forProjectID: projectID, fontID: fontID)
    }

    /// Legacy project-wide setter — prefer `setNameIDStrategy(forProjectID:fontID:)`.
    func setNameIDStrategy(forProjectID projectID: String, strategy: NameIDStrategy) {
        guard let index = openProjects.firstIndex(where: { $0.id == projectID }) else { return }
        var document = openProjects[index].document
        guard document.nameidStrategy != strategy
            || document.fonts.contains(where: { $0.options.nameidStrategy != strategy }) else {
            return
        }
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

    func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    func pushUndoSnapshot() {
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
        linkedStopID: String? = nil,
        code: String? = nil
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
                linkedValue: linkedValue,
                code: InstanceCodeBuilder.sanitize(code)
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

    func mutateSelectedFont(
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

    func backfillMissingInferredAxisRoles() {
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

    static let fontFileExtensions: Set<String> = ["ttf", "otf", "woff", "woff2"]
    static let fontContentTypes: [UTType] = [
        UTType(filenameExtension: "ttf")!,
        UTType(filenameExtension: "otf")!,
        UTType(filenameExtension: "woff")!,
        UTType(filenameExtension: "woff2")!,
    ]
}
