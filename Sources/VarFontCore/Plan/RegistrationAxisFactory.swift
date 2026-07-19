import Foundation

/// Templates and migration for registration (`design_record_only`) axes that absorb file clarifiers.
public enum RegistrationAxisFactory {
    public enum TemplateKind: String, Sendable, CaseIterable {
        case slope
        case width
        case optical

        public var defaultTag: String {
            switch self {
            case .slope: return "ital"
            case .width: return "wdth"
            case .optical: return "opsz"
            }
        }

        public var displayName: String {
            switch self {
            case .slope: return "Slope"
            case .width: return "Width"
            case .optical: return "Optical"
            }
        }

        public var clarifierCategory: FileClarifierCategory {
            switch self {
            case .slope: return .slope
            case .width: return .width
            case .optical: return .optical
            }
        }
    }

    public static func canAddRegistrationAxis(tag: String, axes: [AxisDefinition]) -> Bool {
        let normalized = sanitizeAxisTag(tag)
        guard !normalized.isEmpty else { return false }
        return !axes.contains { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    /// True when any font in the family already uses this tag.
    public static func tagExistsInFamily(tag: String, fonts: [FontDocument]) -> Bool {
        let normalized = sanitizeAxisTag(tag)
        guard !normalized.isEmpty else { return false }
        return fonts.contains { font in
            font.axes.contains { $0.tag.caseInsensitiveCompare(normalized) == .orderedSame }
        }
    }

    public enum AddBlockReason: Equatable, Sendable {
        case available
        /// Tag already present as a design-record / naming axis.
        case namingAxisExists(tag: String)
        /// Tag already present as an instance (fvar) axis.
        case instanceAxisExists(tag: String, rangeDescription: String?)
    }

    public static func addAvailability(
        for kind: TemplateKind,
        axes: [AxisDefinition]
    ) -> AddBlockReason {
        let tag = kind.defaultTag
        guard let existing = axes.first(where: { $0.tag.caseInsensitiveCompare(tag) == .orderedSame }) else {
            return .available
        }
        if existing.isDesignRecordOnly {
            return .namingAxisExists(tag: existing.tag)
        }
        if existing.role == .instance {
            let range: String?
            if let min = existing.min, let max = existing.max {
                range = "\(AxisCoordinateFormat.format(min))–\(AxisCoordinateFormat.format(max))"
            } else {
                range = nil
            }
            return .instanceAxisExists(tag: existing.tag, rangeDescription: range)
        }
        // pinned / other — still a collision
        return .namingAxisExists(tag: existing.tag)
    }

    public static func blockReasonCopy(_ reason: AddBlockReason) -> String? {
        switch reason {
        case .available:
            return nil
        case .namingAxisExists(let tag):
            return "\(tag) already exists as a naming axis in this tree — adding it again would duplicate the tag."
        case .instanceAxisExists(let tag, let range):
            if let range {
                return "\(tag) already exists as an instance axis (fvar \(tag) \(range)) — a naming axis with the same tag would collide."
            }
            return "\(tag) already exists as an instance axis — a naming axis with the same tag would collide."
        }
    }

    /// Prefer existing `slnt` for slope when present; otherwise `ital` if addable.
    public static func templateTag(for kind: TemplateKind, axes: [AxisDefinition]) -> String? {
        switch kind {
        case .slope:
            if axes.contains(where: { $0.tag == "slnt" }) { return nil }
            if axes.contains(where: { $0.tag == "ital" }) { return nil }
            return "ital"
        case .width, .optical:
            let tag = kind.defaultTag
            return axes.contains(where: { $0.tag.caseInsensitiveCompare(tag) == .orderedSame })
                ? nil
                : tag
        }
    }

    public static func makeTemplateAxis(kind: TemplateKind) -> AxisDefinition {
        switch kind {
        case .slope:
            // Default seed is upright; insert path replaces per-file with makeItalAxis.
            return makeItalAxis(isItalicFile: false)
        case .width:
            return AxisDefinition(
                tag: "wdth",
                displayName: "Width",
                role: .designRecordOnly,
                roleInferred: .designRecordOnly,
                values: [
                    AxisValue(
                        id: "wdth-normal",
                        value: 100,
                        name: "Normal",
                        elidable: true,
                        code: nil
                    ),
                ]
            )
        case .optical:
            return AxisDefinition(
                tag: "opsz",
                displayName: "Optical Size",
                role: .designRecordOnly,
                roleInferred: .designRecordOnly,
                values: [
                    AxisValue(
                        id: "opsz-regular",
                        value: 12,
                        name: "Regular",
                        elidable: true,
                        code: nil
                    ),
                ]
            )
        }
    }

    /// Playfair-style `ital`: one Format 3 stop per file.
    /// Roman VF → `0` Roman elided, linked to `1`. Italic VF → `1` Italic, linked to `0`.
    public static func makeItalAxis(isItalicFile: Bool) -> AxisDefinition {
        if isItalicFile {
            return AxisDefinition(
                tag: "ital",
                displayName: "Italic",
                role: .designRecordOnly,
                roleInferred: .designRecordOnly,
                values: [
                    AxisValue(
                        id: "ital-italic",
                        value: 1,
                        name: "Italic",
                        elidable: false,
                        statFormat: 3,
                        linkedValue: 0,
                        code: "1"
                    ),
                ]
            )
        }
        return AxisDefinition(
            tag: "ital",
            displayName: "Italic",
            role: .designRecordOnly,
            roleInferred: .designRecordOnly,
            values: [
                AxisValue(
                    id: "ital-roman",
                    value: 0,
                    name: "Roman",
                    elidable: true,
                    statFormat: 3,
                    linkedValue: 1,
                    code: "0"
                ),
            ]
        )
    }

    public static func makeCustomAxis(
        tag: String,
        displayName: String,
        value: Double = 0,
        elidable: Bool = true,
        code: String? = nil
    ) -> AxisDefinition {
        let normalized = sanitizeAxisTag(tag)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stopName = name.isEmpty ? normalized : name
        return AxisDefinition(
            tag: normalized,
            displayName: name.isEmpty ? nil : name,
            role: .designRecordOnly,
            roleInferred: .designRecordOnly,
            values: [
                AxisValue(
                    id: "\(normalized)-0",
                    value: value,
                    name: stopName,
                    elidable: elidable,
                    code: InstanceCodeBuilder.sanitize(code)
                ),
            ]
        )
    }

    public static func makeNamedStopAxis(
        tag: String,
        displayName: String,
        stopName: String,
        value: Double,
        elidable: Bool = false,
        code: String? = nil
    ) -> AxisDefinition {
        let normalized = sanitizeAxisTag(tag)
        let axisName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStop = stopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stopLabel = resolvedStop.isEmpty
            ? (axisName.isEmpty ? normalized : axisName)
            : resolvedStop
        return AxisDefinition(
            tag: normalized,
            displayName: axisName.isEmpty ? nil : axisName,
            role: .designRecordOnly,
            roleInferred: .designRecordOnly,
            values: [
                AxisValue(
                    id: "\(normalized)-\(UUID().uuidString.prefix(8))",
                    value: value,
                    name: stopLabel,
                    elidable: elidable,
                    code: InstanceCodeBuilder.sanitize(code)
                ),
            ]
        )
    }

    /// Insert a naming axis into the project.
    /// - `ital`: every file gets its Playfair-style single stop (Roman or Italic).
    /// - Other tags: only `selectedFontID` receives the populated stop; siblings are left alone
    ///   until someone adds a stop on those files. Template always records the axis.
    @discardableResult
    public static func insertNamingAxis(
        _ axis: AxisDefinition,
        into project: inout ProjectDocument,
        selectedFontID: String,
        italicOverride: Bool? = nil
    ) -> Bool {
        if axis.tag == "ital" {
            var changed = false
            for index in project.fonts.indices {
                guard !project.fonts[index].axes.contains(where: { $0.tag == "ital" }) else { continue }
                // The override only reflects the user's judgment call for the file they're actively
                // editing; every other sibling still gets auto-detected from its own filename/style.
                let italic = (project.fonts[index].id == selectedFontID ? italicOverride : nil)
                    ?? RegistrationAxisSupport.isItalicFile(font: project.fonts[index])
                let axisForFile = makeItalAxis(isItalicFile: italic)
                project.fonts[index].axes.append(axisForFile)
                project.fonts[index].fileStatRegistration["ital"] = axisForFile.values.first?.value ?? 0
                syncStatDesignAxisTags(on: &project.fonts[index])
                project.fonts[index].dirty = true
                changed = true
            }
            if !project.template.axes.contains(where: { $0.tag == "ital" }) {
                project.template.axes.append(makeItalAxis(isItalicFile: false))
                changed = true
            }
            if !project.naming.order.contains("ital") {
                project.naming.order.append("ital")
                project.naming.order = NamingPolicy.ensurePostscriptHyphen(in: project.naming.order)
                changed = true
            }
            project.naming.order = project.naming.order.filter { !NamingToken.isClarifier($0) }
            if changed { project.modified = Date() }
            return changed
        }

        guard let index = project.fonts.firstIndex(where: { $0.id == selectedFontID }) else {
            return false
        }
        guard !project.fonts[index].axes.contains(where: {
            $0.tag.caseInsensitiveCompare(axis.tag) == .orderedSame
        }) else {
            return false
        }

        project.fonts[index].axes.append(axis)
        project.fonts[index].fileStatRegistration[axis.tag] = axis.values.first?.value ?? 0
        syncStatDesignAxisTags(on: &project.fonts[index])
        project.fonts[index].dirty = true

        if !project.template.axes.contains(where: {
            $0.tag.caseInsensitiveCompare(axis.tag) == .orderedSame
        }) {
            project.template.axes.append(axis)
        }
        if !project.naming.order.contains(axis.tag) {
            project.naming.order.append(axis.tag)
            project.naming.order = NamingPolicy.ensurePostscriptHyphen(in: project.naming.order)
        }
        project.naming.order = project.naming.order.filter { !NamingToken.isClarifier($0) }
        project.modified = Date()
        return true
    }

    /// Letters/digits only; at most 4 characters. Preserves case (upper ≈ registered-style, lower ≈ private-use).
    public static func sanitizeAxisTag(_ raw: String) -> String {
        String(raw.filter { $0.isLetter || $0.isNumber }.prefix(4))
    }

    /// Promote leftover `file_role.clarifiers` into registration axes + `file_stat_registration`.
    /// Returns `true` when the project document changed.
    @discardableResult
    public static func promoteClarifiersToRegistration(_ project: inout ProjectDocument) -> Bool {
        guard project.fonts.contains(where: { !($0.fileRole?.clarifiers.isEmpty ?? true) }) else {
            return rewriteNamingOrderRemovingOrphanClarifiers(&project)
        }

        var changed = false
        var promotedTags: [FileClarifierCategory: String] = [:]

        for category in [FileClarifierCategory.slope, .width, .optical, .custom] {
            let entries = clarifierEntries(for: category, in: project)
            guard !entries.isEmpty else { continue }

            if category == .slope {
                if coveringAxisTag(for: .slope, axes: project.fonts.first?.axes ?? []) != nil {
                    promotedTags[.slope] = coveringAxisTag(for: .slope, axes: project.fonts.first?.axes ?? [])!
                    for index in project.fonts.indices {
                        if clearClarifier(.slope, on: &project.fonts[index]) { changed = true }
                    }
                    continue
                }
                guard canAddRegistrationAxis(tag: "ital", axes: project.fonts.first?.axes ?? []) else {
                    continue
                }
                promotedTags[.slope] = "ital"
                for index in project.fonts.indices {
                    let fontID = project.fonts[index].id
                    let isItalic: Bool = {
                        if let entry = entries.first(where: { $0.fontID == fontID }) {
                            let label = resolvedStopName(entry: entry, category: .slope)
                            return entry.isItalicFile
                                || RegistrationAxisSupport.isItalicLikeStopName(label)
                        }
                        return RegistrationAxisSupport.isItalicFile(font: project.fonts[index])
                    }()
                    let axis = makeItalAxis(isItalicFile: isItalic)
                    if !project.fonts[index].axes.contains(where: { $0.tag == "ital" }) {
                        project.fonts[index].axes.append(axis)
                        syncStatDesignAxisTags(on: &project.fonts[index])
                    }
                    if let stop = axis.values.first {
                        project.fonts[index].fileStatRegistration["ital"] = stop.value
                        // Prefer clarifier code when present.
                        if let entry = entries.first(where: { $0.fontID == fontID }),
                           let code = InstanceCodeBuilder.sanitize(entry.clarifier.code),
                           let stopIndex = project.fonts[index].axes.firstIndex(where: { $0.tag == "ital" }),
                           let valueIndex = project.fonts[index].axes[stopIndex].values.firstIndex(where: {
                               AxisCoordinate.valuesEqual($0.value, stop.value)
                           }) {
                            project.fonts[index].axes[stopIndex].values[valueIndex].code = code
                        }
                    }
                    if clearClarifier(.slope, on: &project.fonts[index]) { changed = true }
                    project.fonts[index].dirty = true
                }
                if !project.template.axes.contains(where: { $0.tag == "ital" }) {
                    project.template.axes.append(makeItalAxis(isItalicFile: false))
                }
                changed = true
                continue
            }

            if let existing = coveringAxisTag(for: category, axes: project.fonts.first?.axes ?? []) {
                promotedTags[category] = existing
                for index in project.fonts.indices {
                    if clearClarifier(category, on: &project.fonts[index]) {
                        changed = true
                    }
                }
                continue
            }

            guard let axis = buildPromotedAxis(category: category, entries: entries, project: project) else {
                continue
            }
            promotedTags[category] = axis.tag
            insertAxis(axis, into: &project)
            for index in project.fonts.indices {
                let fontID = project.fonts[index].id
                if let entry = entries.first(where: { $0.fontID == fontID }),
                   let value = registrationValue(for: entry, on: axis) {
                    project.fonts[index].fileStatRegistration[axis.tag] = value
                } else if let elidable = axis.values.first(where: \.elidable)?.value
                    ?? axis.values.first?.value {
                    project.fonts[index].fileStatRegistration[axis.tag] = elidable
                }
                if clearClarifier(category, on: &project.fonts[index]) {
                    changed = true
                }
                project.fonts[index].dirty = true
            }
            changed = true
        }

        if rewriteNamingOrder(promotedTags: promotedTags, project: &project) {
            changed = true
        }
        if changed {
            project.modified = Date()
        }
        return changed
    }

    // MARK: - Private

    private struct ClarifierEntry {
        var fontID: String
        var clarifier: FileClarifier
        var isItalicFile: Bool
    }

    private static func clarifierEntries(
        for category: FileClarifierCategory,
        in project: ProjectDocument
    ) -> [ClarifierEntry] {
        project.fonts.compactMap { font in
            guard let clarifier = font.fileRole?.clarifiers.first(where: { $0.category == category }) else {
                return nil
            }
            let hasLabel = !clarifier.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasCode = InstanceCodeBuilder.sanitize(clarifier.code) != nil
            guard hasLabel || hasCode else { return nil }
            return ClarifierEntry(
                fontID: font.id,
                clarifier: clarifier,
                isItalicFile: RegistrationAxisSupport.isItalicFile(font: font)
            )
        }
    }

    private static func coveringAxisTag(for category: FileClarifierCategory, axes: [AxisDefinition]) -> String? {
        switch category {
        case .slope:
            if let ital = axes.first(where: { $0.tag == "ital" }) { return ital.tag }
            if let slnt = axes.first(where: { $0.tag == "slnt" }) { return slnt.tag }
            return nil
        case .width:
            return axes.contains(where: { $0.tag == "wdth" }) ? "wdth" : nil
        case .optical:
            return axes.contains(where: { $0.tag == "opsz" }) ? "opsz" : nil
        case .custom:
            return nil
        }
    }

    private static func buildPromotedAxis(
        category: FileClarifierCategory,
        entries: [ClarifierEntry],
        project: ProjectDocument
    ) -> AxisDefinition? {
        let axes = project.fonts.first?.axes ?? []
        switch category {
        case .slope:
            // Per-file single-stop axes are inserted by promoteClarifiersToRegistration.
            return nil
        case .width:
            guard canAddRegistrationAxis(tag: "wdth", axes: axes) else { return nil }
            var axis = makeTemplateAxis(kind: .width)
            axis = mergeStops(into: axis, from: entries, category: .width)
            return axis
        case .optical:
            guard canAddRegistrationAxis(tag: "opsz", axes: axes) else { return nil }
            var axis = makeTemplateAxis(kind: .optical)
            axis = mergeStops(into: axis, from: entries, category: .optical)
            return axis
        case .custom:
            let label = entries.first?.clarifier.label
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var tag = sanitizeAxisTag(label)
            if tag.trimmingCharacters(in: .whitespaces).isEmpty {
                tag = "CUST"
            }
            if !canAddRegistrationAxis(tag: tag, axes: axes) {
                tag = uniqueCustomTag(preferred: tag, axes: axes)
            }
            guard canAddRegistrationAxis(tag: tag, axes: axes) else { return nil }
            var axis = makeCustomAxis(tag: tag, displayName: label.isEmpty ? "Custom" : label)
            axis = mergeStops(into: axis, from: entries, category: .custom)
            return axis
        }
    }

    private static func uniqueCustomTag(preferred: String, axes: [AxisDefinition]) -> String {
        let base = sanitizeAxisTag(preferred.isEmpty ? "CUST" : preferred)
        if canAddRegistrationAxis(tag: base, axes: axes) { return base }
        for suffix in 0..<36 {
            let ch = suffix < 10 ? String(suffix) : String(Character(UnicodeScalar(55 + suffix)!))
            var candidate = String(base.prefix(3)) + ch
            candidate = sanitizeAxisTag(candidate)
            if canAddRegistrationAxis(tag: candidate, axes: axes) { return candidate }
        }
        return ""
    }

    private static func mergeStops(
        into axis: AxisDefinition,
        from entries: [ClarifierEntry],
        category: FileClarifierCategory
    ) -> AxisDefinition {
        var result = axis
        for entry in entries {
            let label = resolvedStopName(entry: entry, category: category)
            let code = InstanceCodeBuilder.sanitize(entry.clarifier.code)
            if let existing = result.values.firstIndex(where: {
                $0.name.caseInsensitiveCompare(label) == .orderedSame
            }) {
                if result.values[existing].code == nil, let code {
                    result.values[existing].code = code
                }
                continue
            }
            let value: Double
            if category == .slope {
                value = RegistrationAxisSupport.isItalicLikeStopName(label)
                    || entry.isItalicFile && !RegistrationAxisSupport.isUprightLikeStopName(label)
                    ? 1 : 0
                if result.values.contains(where: { AxisCoordinate.valuesEqual($0.value, value) }) {
                    // Keep template stop; attach code if needed.
                    if let idx = result.values.firstIndex(where: { AxisCoordinate.valuesEqual($0.value, value) }),
                       result.values[idx].code == nil, let code {
                        result.values[idx].code = code
                    }
                    continue
                }
            } else {
                value = (result.values.map(\.value).max() ?? -1) + 1
            }
            let elidable = category == .slope
                ? RegistrationAxisSupport.isUprightLikeStopName(label)
                : entry.clarifier.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            result.values.append(
                AxisValue(
                    id: "\(result.tag)-\(UUID().uuidString.prefix(8))",
                    value: value,
                    name: label,
                    elidable: elidable,
                    code: code
                )
            )
        }
        result.values.sort { $0.value < $1.value }
        return result
    }

    private static func resolvedStopName(entry: ClarifierEntry, category: FileClarifierCategory) -> String {
        let trimmed = entry.clarifier.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if category == .slope {
            if entry.clarifier.code == "0" || !entry.isItalicFile { return "Roman" }
            return "Italic"
        }
        return "Default"
    }

    private static func registrationValue(for entry: ClarifierEntry, on axis: AxisDefinition) -> Double? {
        let label = resolvedStopName(
            entry: entry,
            category: entry.clarifier.category
        )
        if let match = axis.values.first(where: { $0.name.caseInsensitiveCompare(label) == .orderedSame }) {
            return match.value
        }
        if entry.clarifier.category == .slope {
            if entry.isItalicFile,
               let italic = axis.values.first(where: { RegistrationAxisSupport.isItalicLikeStopName($0.name) }) {
                return italic.value
            }
            if let upright = RegistrationAxisSupport.uprightStop(on: axis) {
                return upright.value
            }
        }
        return axis.values.first(where: \.elidable)?.value ?? axis.values.first?.value
    }

    private static func insertAxis(_ axis: AxisDefinition, into project: inout ProjectDocument) {
        for index in project.fonts.indices {
            guard !project.fonts[index].axes.contains(where: { $0.tag == axis.tag }) else { continue }
            project.fonts[index].axes.append(axis)
            syncStatDesignAxisTags(on: &project.fonts[index])
        }
        if !project.template.axes.contains(where: { $0.tag == axis.tag }) {
            project.template.axes.append(axis)
        }
    }

    /// Keep import-time STAT tag list aligned with the live Axis Tree order.
    private static func syncStatDesignAxisTags(on font: inout FontDocument) {
        font.statDesignAxisTags = font.axes.map(\.tag)
    }

    @discardableResult
    private static func clearClarifier(_ category: FileClarifierCategory, on font: inout FontDocument) -> Bool {
        guard var role = font.fileRole, role.clarifiers.contains(where: { $0.category == category }) else {
            return false
        }
        role.clarifiers.removeAll { $0.category == category }
        font.fileRole = role
        return true
    }

    private static func rewriteNamingOrder(
        promotedTags: [FileClarifierCategory: String],
        project: inout ProjectDocument
    ) -> Bool {
        let original = project.naming.order
        var result: [String] = []
        var seen = Set<String>()
        for token in original {
            if let category = NamingToken.clarifierCategory(for: token) {
                if let tag = promotedTags[category], !seen.contains(tag) {
                    result.append(tag)
                    seen.insert(tag)
                }
                // Drop clarifier token (promoted or orphan).
                continue
            }
            if !seen.contains(token) {
                result.append(token)
                seen.insert(token)
            }
        }
        for tag in promotedTags.values where !seen.contains(tag) {
            result.append(tag)
            seen.insert(tag)
        }
        let normalized = NamingPolicy.ensurePostscriptHyphen(in: result)
        guard normalized != original else { return false }
        project.naming.order = normalized
        return true
    }

    private static func rewriteNamingOrderRemovingOrphanClarifiers(_ project: inout ProjectDocument) -> Bool {
        let original = project.naming.order
        let filtered = original.filter { !NamingToken.isClarifier($0) }
        let normalized = NamingPolicy.ensurePostscriptHyphen(in: filtered)
        guard normalized != original else { return false }
        project.naming.order = normalized
        project.modified = Date()
        return true
    }
}
