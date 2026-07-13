import Foundation

public enum PlanIssueCodes {
    public static let resolvable: Set<String> = [
        "registration_value_missing",
        "registration_mismatch",
        "orphan_stat_link",
        "ital_value_name_mismatch",
        "ital_format1_upgrade",
        "wght_format1_upgrade",
        "default_token_names",
        "axis_neutral_mismatch",
        "duplicate_composed_name",
        "multiple_elidable",
        "empty_instance_axis",
        "fvar_missing_from_stat",
        "stat_missing_from_fvar",
        "ital_slnt_coexistence",
        "default_instance_excluded",
        "default_instance_not_in_grid",
    ]

    public static func issueKey(for warning: PlanWarning) -> String {
        let axis = warning.axis ?? ""
        let stops = (warning.stopIDs ?? []).sorted().joined(separator: ",")
        return "\(warning.code):\(axis):\(stops)"
    }
}

public enum PlanIssueAction: Equatable, Sendable {
    case setFileRegistration(tag: String, value: Double)
    case revalueStop(axisTag: String, stopID: String, newValue: Double)
    case convertStopToFormat1(axisTag: String, stopID: String)
    case updateStopFormat3Link(axisTag: String, stopID: String, linkedValue: Double)
    case renameStop(axisTag: String, stopID: String, newName: String)
    case applyAxisDefaults
    case applyAxisNeutrals
    case normalizeElidable(axisTag: String)
    case clearAllElidable(axisTag: String)
    case setAxisRole(axisTag: String, role: AxisRole)
    case insertAxisStop(axisTag: String, value: Double, name: String)
    case insertAxisStops(axisTag: String, values: [Double])
    case openAxisConflicts(axisTag: String?)
    case includeInstanceKey(String)
    case acknowledgeIssue(issueKey: String)
    case compound([PlanIssueAction])
}

public struct PlanIssueProposal: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var action: PlanIssueAction
    public var isRecommended: Bool

    public init(
        id: String,
        title: String,
        detail: String,
        action: PlanIssueAction,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.isRecommended = isRecommended
    }
}

public enum PlanIssueResolver {
    // MARK: - Proposals

    public static func proposals(for warning: PlanWarning, font: FontDocument) -> [PlanIssueProposal] {
        guard PlanIssueCodes.resolvable.contains(warning.code) else { return [] }
        switch warning.code {
        case "registration_value_missing":
            return registrationValueMissingProposals(for: warning, font: font)
        case "registration_mismatch":
            return registrationMismatchProposals(for: warning, font: font)
        case "orphan_stat_link":
            return orphanStatLinkProposals(for: warning, font: font)
        case "ital_value_name_mismatch":
            return italConventionProposals(for: warning, font: font)
        case "ital_format1_upgrade", "wght_format1_upgrade":
            return format1UpgradeProposals(for: warning, font: font)
        case "default_token_names", "axis_neutral_mismatch":
            return defaultTokenNamesProposals(for: warning, font: font)
        case "duplicate_composed_name":
            return duplicateComposedNameProposals(for: warning, font: font)
        case "multiple_elidable":
            return multipleElidableProposals(for: warning, font: font)
        case "empty_instance_axis":
            return emptyInstanceAxisProposals(for: warning, font: font)
        case "ital_slnt_coexistence":
            return italSlntCoexistenceProposals(for: warning, font: font)
        case "fvar_missing_from_stat", "stat_missing_from_fvar":
            return acknowledgeOnlyProposals(for: warning)
        case "default_instance_not_in_grid":
            return defaultInstanceNotInGridProposals(for: warning, font: font)
        case "default_instance_excluded":
            return defaultInstanceExcludedProposals(for: warning, font: font)
        default:
            return []
        }
    }

    public static func recommendedProposal(for warning: PlanWarning, font: FontDocument) -> PlanIssueProposal? {
        guard let proposal = proposals(for: warning, font: font).first(where: \.isRecommended) else {
            return nil
        }
        guard wouldApply(proposal.action, to: font) else { return nil }
        return proposal
    }

    public static func wouldApply(_ action: PlanIssueAction, to font: FontDocument) -> Bool {
        switch action {
        case .applyAxisNeutrals:
            return AxisStopNamingDefaults.wouldChangeFromApplyAxisNeutrals(font)
        case .applyAxisDefaults:
            return AxisStopNamingDefaults.wouldChangeFromApplyAxisDefaults(font)
        case .normalizeElidable(let axisTag):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }) else { return false }
            return axis.values.filter(\.elidable).count > 1
        case .clearAllElidable(let axisTag):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }) else { return false }
            return axis.values.contains(where: \.elidable)
        case .setAxisRole(let axisTag, let role):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }) else { return false }
            guard !axis.isDesignRecordOnly else { return false }
            return axis.role != role
        case .insertAxisStop(let axisTag, let value, _):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }) else { return false }
            guard axis.role == .instance, !axis.isDesignRecordOnly else { return false }
            return !axis.values.contains { AxisCoordinate.valuesEqual($0.value, value) }
        case .insertAxisStops(let axisTag, _):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }) else { return false }
            return axis.role == .instance && axis.values.isEmpty && !axis.isDesignRecordOnly
        case .openAxisConflicts:
            return AxisStopNamingDefaults.hasInstanceAxisValueConflicts(font)
        case .setFileRegistration, .convertStopToFormat1, .renameStop:
            return true
        case .revalueStop(let axisTag, let stopID, let newValue):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }),
                  let stop = axis.values.first(where: { $0.id == stopID }) else { return false }
            return !AxisCoordinate.valuesEqual(stop.value, newValue)
                && !axis.values.contains { $0.id != stopID && AxisCoordinate.valuesEqual($0.value, newValue) }
        case let .updateStopFormat3Link(axisTag, stopID, linkedValue):
            guard let axis = font.axes.first(where: { $0.tag == axisTag }),
                  let stop = axis.values.first(where: { $0.id == stopID }) else { return false }
            if stop.statFormat != 3 { return true }
            guard let current = stop.linkedValue else { return true }
            return !AxisCoordinate.valuesEqual(current, linkedValue)
        case let .includeInstanceKey(key):
            return font.excludedInstanceKeys.contains(key)
                || (!font.includedInstanceKeys.isEmpty && !font.includedInstanceKeys.contains(key))
        case let .acknowledgeIssue(issueKey):
            return !font.dismissedPlanIssues.contains(issueKey)
        case .compound(let actions):
            return actions.contains { wouldApply($0, to: font) }
        }
    }

    public static func canApplyWithoutSheet(for warning: PlanWarning, font: FontDocument) -> Bool {
        let proposals = proposals(for: warning, font: font)
        guard proposals.count == 1, let only = proposals.first, only.isRecommended else { return false }
        if case .acknowledgeIssue = only.action { return false }
        return true
    }

    public static func canChainApply(for warning: PlanWarning, font: FontDocument) -> Bool {
        guard let proposal = recommendedProposal(for: warning, font: font), proposal.isRecommended else {
            return false
        }
        return isChainableAction(proposal.action)
    }

    // MARK: - Apply

    public static func apply(_ action: PlanIssueAction, to font: inout FontDocument) {
        switch action {
        case let .compound(actions):
            for step in actions {
                apply(step, to: &font)
            }
        case .applyAxisDefaults:
            AxisStopNamingDefaults.applyAxisDefaultsToAllInstanceAxes(font: &font)
        case .applyAxisNeutrals:
            AxisStopNamingDefaults.applyAxisNeutralsToAllInstanceAxes(font: &font)
        case let .normalizeElidable(axisTag):
            normalizeElidable(on: axisTag, font: &font)
        case let .clearAllElidable(axisTag):
            clearAllElidable(on: axisTag, font: &font)
        case let .setFileRegistration(tag, value):
            font.fileStatRegistration[tag] = value
        case let .revalueStop(axisTag, stopID, newValue):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            let previousValue = font.axes[axisIndex].values[stopIndex].value
            let wasRegistered = font.fileStatRegistration[axisTag]
                .map { AxisCoordinate.valuesEqual($0, previousValue) } ?? false
            font.axes[axisIndex].values[stopIndex].value = newValue
            font.axes[axisIndex].values.sort { $0.value < $1.value }
            if wasRegistered {
                font.fileStatRegistration[axisTag] = newValue
            }
        case let .convertStopToFormat1(axisTag, stopID):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            font.axes[axisIndex].values[stopIndex].statFormat = 1
            font.axes[axisIndex].values[stopIndex].linkedValue = nil
        case let .updateStopFormat3Link(axisTag, stopID, linkedValue):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            font.axes[axisIndex].values[stopIndex].statFormat = 3
            font.axes[axisIndex].values[stopIndex].linkedValue = linkedValue
            font.axes[axisIndex].values[stopIndex].rangeMin = nil
            font.axes[axisIndex].values[stopIndex].rangeMax = nil
        case let .renameStop(axisTag, stopID, newName):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }),
                  let stopIndex = font.axes[axisIndex].values.firstIndex(where: { $0.id == stopID }) else { return }
            font.axes[axisIndex].values[stopIndex].name = newName
        case let .setAxisRole(axisTag, role):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            guard !font.axes[axisIndex].isDesignRecordOnly else { return }
            font.axes[axisIndex].role = role
        case let .insertAxisStop(axisTag, value, name):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            guard font.axes[axisIndex].role == .instance, !font.axes[axisIndex].isDesignRecordOnly else { return }
            guard !font.axes[axisIndex].values.contains(where: { AxisCoordinate.valuesEqual($0.value, value) }) else { return }
            let stopID = "\(axisTag)-\(UUID().uuidString.prefix(8))"
            let stop = AxisValue(
                id: stopID,
                value: value,
                name: name,
                elidable: false,
                statFormat: 1,
                rangeMin: nil,
                rangeMax: nil,
                linkedValue: nil
            )
            font.axes[axisIndex].values.append(stop)
            font.axes[axisIndex].values.sort { $0.value < $1.value }
        case let .insertAxisStops(axisTag, values):
            guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
            guard font.axes[axisIndex].role == .instance,
                  font.axes[axisIndex].values.isEmpty,
                  !font.axes[axisIndex].isDesignRecordOnly else { return }
            for value in values {
                let canonical = AxisCoordinateFormat.canonical(value)
                let stop = AxisValue(
                    id: "\(axisTag)-\(UUID().uuidString.prefix(8))",
                    value: canonical,
                    name: AxisStopSuggestions.formatValue(canonical),
                    elidable: false,
                    statFormat: 1,
                    rangeMin: nil,
                    rangeMax: nil,
                    linkedValue: nil
                )
                font.axes[axisIndex].values.append(stop)
            }
            font.axes[axisIndex].values.sort { $0.value < $1.value }
        case .openAxisConflicts:
            break
        case let .includeInstanceKey(key):
            font.excludedInstanceKeys.removeAll { $0 == key }
            if !font.includedInstanceKeys.isEmpty, !font.includedInstanceKeys.contains(key) {
                font.includedInstanceKeys.append(key)
            }
        case let .acknowledgeIssue(issueKey):
            if !font.dismissedPlanIssues.contains(issueKey) {
                font.dismissedPlanIssues.append(issueKey)
            }
        }
    }

    // MARK: - Auto-fix (import only)

    public struct SafeAutoFixResult: Equatable, Sendable {
        public var appliedCount: Int
        /// True when the iteration cap was hit but another safe auto-fix was still available.
        public var hitIterationLimit: Bool

        public init(appliedCount: Int, hitIterationLimit: Bool) {
            self.appliedCount = appliedCount
            self.hitIterationLimit = hitIterationLimit
        }
    }

    public static let safeAutoFixMaxIterations = 32

    @discardableResult
    public static func applySafeAutoFixes(
        to font: inout FontDocument,
        analysis: FontAnalysis? = nil
    ) -> SafeAutoFixResult {
        var applied = 0
        for _ in 0..<safeAutoFixMaxIterations {
            guard let proposal = nextSafeAutoFixProposal(for: font, analysis: analysis) else { break }
            apply(proposal.action, to: &font)
            applied += 1
        }
        let hitLimit = applied == safeAutoFixMaxIterations
            && nextSafeAutoFixProposal(for: font, analysis: analysis) != nil
        return SafeAutoFixResult(appliedCount: applied, hitIterationLimit: hitLimit)
    }

    private static func nextSafeAutoFixProposal(
        for font: FontDocument,
        analysis: FontAnalysis?
    ) -> PlanIssueProposal? {
        let warnings = visibleWarnings(for: font, analysis: analysis)
        guard let warning = warnings.first(where: { warning in
            guard let proposal = recommendedProposal(for: warning, font: font),
                  proposal.isRecommended,
                  isSafeAutoFixAction(proposal.action) else {
                return false
            }
            return true
        }) else {
            return nil
        }
        return recommendedProposal(for: warning, font: font)
    }

    public static func visibleWarnings(for font: FontDocument, analysis: FontAnalysis? = nil) -> [PlanWarning] {
        let all = RegistrationAxisSupport.allRegistrationPlanWarnings(font: font, analysis: analysis)
            + StatFormat3Pairing.orphanLinkWarnings(axes: font.axes)
        return all.filter { !font.dismissedPlanIssues.contains(PlanIssueCodes.issueKey(for: $0)) }
    }

    // MARK: - Private

    private static func isSafeAutoFixAction(_ action: PlanIssueAction) -> Bool {
        switch action {
        case .setFileRegistration, .revalueStop:
            return true
        case .convertStopToFormat1, .renameStop, .acknowledgeIssue, .applyAxisDefaults, .applyAxisNeutrals,
             .normalizeElidable, .clearAllElidable, .setAxisRole, .insertAxisStop, .insertAxisStops,
             .updateStopFormat3Link, .includeInstanceKey, .openAxisConflicts:
            return false
        case .compound(let actions):
            return actions.allSatisfy(isSafeAutoFixAction)
        }
    }

    private static func isChainableAction(_ action: PlanIssueAction) -> Bool {
        switch action {
        case .setFileRegistration, .revalueStop, .convertStopToFormat1, .updateStopFormat3Link, .applyAxisDefaults, .applyAxisNeutrals,
             .normalizeElidable, .clearAllElidable, .setAxisRole, .insertAxisStop, .insertAxisStops, .includeInstanceKey:
            return true
        case .renameStop, .acknowledgeIssue, .openAxisConflicts:
            return false
        case .compound(let actions):
            return actions.allSatisfy(isChainableAction)
        }
    }

    private static func registrationValueMissingProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let axis = font.axes.first(where: { $0.tag == tag }),
              axis.isDesignRecordOnly else { return [] }
        guard !axis.values.isEmpty else { return [] }

        if let inferred = RegistrationAxisSupport.inferRegistrationValue(
            forTag: tag,
            axes: font.axes,
            sourcePath: font.sourcePath,
            inferredIsItalicFile: font.inferredIsItalicFile
        ) {
            return [
                PlanIssueProposal(
                    id: "reg-missing-infer",
                    title: "Use inferred registration",
                    detail: "Set registration to \(AxisCoordinateFormat.format(inferred)) on axis '\(tag)'.",
                    action: .setFileRegistration(tag: tag, value: inferred),
                    isRecommended: true
                ),
            ]
        }
        return []
    }

    private static func registrationMismatchProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let axis = font.axes.first(where: { $0.tag == tag }) else { return [] }

        var proposals: [PlanIssueProposal] = []

        if let upright = RegistrationAxisSupport.uprightStop(on: axis) {
            proposals.append(
                PlanIssueProposal(
                    id: "reg-mismatch-upright",
                    title: "Use Roman registration",
                    detail: "Register this file as “\(upright.name)” on axis '\(tag)'.",
                    action: .setFileRegistration(tag: tag, value: upright.value),
                    isRecommended: true
                )
            )
        }

        if proposals.isEmpty,
           let regValue = font.fileStatRegistration[tag],
           let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: regValue) {
            proposals.append(
                PlanIssueProposal(
                    id: "reg-mismatch-rename",
                    title: "Rename stop to Roman",
                    detail: "Rename “\(stop.name)” to Roman so registration matches an upright file.",
                    action: .renameStop(axisTag: tag, stopID: stop.id, newName: "Roman"),
                    isRecommended: true
                )
            )
        }

        for stop in axis.values where !proposals.contains(where: {
            if case let .setFileRegistration(t, v) = $0.action { return t == tag && AxisCoordinate.valuesEqual(v, stop.value) }
            return false
        }) {
            proposals.append(
                PlanIssueProposal(
                    id: "reg-pick-\(stop.id)",
                    title: "Use “\(stop.name)”",
                    detail: "Register this file as “\(stop.name)” on axis '\(tag)'.",
                    action: .setFileRegistration(tag: tag, value: stop.value)
                )
            )
        }

        proposals.append(
            PlanIssueProposal(
                id: "reg-mismatch-keep",
                title: "Keep current registration",
                detail: "Leave registration as-is.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            )
        )
        return proposals
    }

    private static func orphanStatLinkProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let stopID = warning.stopIDs?.first,
              let axis = font.axes.first(where: { $0.tag == tag }),
              let stop = axis.values.first(where: { $0.id == stopID }) else { return [] }

        if let compound = compoundOrphanItalProposal(
            axisTag: tag,
            stopID: stopID,
            stop: stop,
            font: font,
            warning: warning
        ) {
            return [compound]
        }

        if StatFormat3Pairing.isConventionStyleLink(axis: axis, stop: stop) {
            return []
        }

        return [
            PlanIssueProposal(
                id: "orphan-convert-f1",
                title: "Keep as standalone style value (Format 1)",
                detail: "Remove the broken Format 3 link on “\(stop.name)” and keep it as a standalone stop.",
                action: .convertStopToFormat1(axisTag: tag, stopID: stopID),
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "orphan-keep-f3",
                title: "Keep Format 3 link",
                detail: "Accept the source font’s link as-is.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func format1UpgradeProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let stopID = warning.stopIDs?.first,
              let axis = font.axes.first(where: { $0.tag == tag }),
              let stop = axis.values.first(where: { $0.id == stopID }),
              StatFormat3Pairing.shouldUpgradeStopToFormat3(stop: stop, axis: axis),
              let linked = StatFormat3Pairing.format3LinkedValue(for: stop.value, axisTag: tag) else { return [] }

        let linkedLabel = StatFormat3Pairing.format3LinkedLabel(axisTag: tag, linkedValue: linked)
        return [
            PlanIssueProposal(
                id: "\(tag)-upgrade-f3",
                title: "Add alternate style name link (Format 3)",
                detail: "Link “\(stop.name)” to \(linkedLabel).",
                action: .updateStopFormat3Link(axisTag: tag, stopID: stopID, linkedValue: linked),
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "\(tag)-keep-f1",
                title: "Keep Format 1",
                detail: "Leave “\(stop.name)” as a standalone Format 1 stop.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func acknowledgeOnlyProposals(for warning: PlanWarning) -> [PlanIssueProposal] {
        dontChangeProposals(for: warning)
    }

    private static func suggestionProposals(for warning: PlanWarning) -> [PlanIssueProposal] {
        dontChangeProposals(for: warning)
    }

    private static func dontChangeProposals(for warning: PlanWarning) -> [PlanIssueProposal] {
        [
            PlanIssueProposal(
                id: "keep-\(warning.code)",
                title: "Don't change",
                detail: warning.hint ?? "Leave this as-is for the current save plan.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning)),
                isRecommended: true
            ),
        ]
    }

    private static func italSlntCoexistenceProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        var proposals = dontChangeProposals(for: warning)

        if let ital = font.axes.first(where: { $0.tag == "ital" }),
           ital.role == .instance,
           !ital.isDesignRecordOnly {
            proposals.append(
                PlanIssueProposal(
                    id: "ital-slnt-registration-only",
                    title: "Make ital registration-only",
                    detail: "Take ital off the instance grid so slnt handles slope variation and naming.",
                    action: .setAxisRole(axisTag: "ital", role: .designRecordOnly)
                )
            )
        }

        return proposals
    }

    private static func defaultInstanceNotInGridProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let axis = font.axes.first(where: { $0.tag == tag }),
              axis.role == .instance,
              let defaultValue = axis.default else {
            return suggestionProposals(for: warning)
        }

        let defaultText = AxisCoordinateFormat.format(defaultValue)
        let label = axis.displayName ?? tag
        var proposals: [PlanIssueProposal] = []

        if let nearest = OpenTypeAxisAudit.nearestStop(in: axis, to: defaultValue),
           !AxisCoordinate.valuesEqual(nearest.value, defaultValue) {
            let distance = abs(nearest.value - defaultValue)
            let fromText = AxisCoordinateFormat.format(nearest.value)
            let preferSnap = distance <= OpenTypeAxisAudit.nearbyDefaultSnapThreshold
            proposals.append(
                PlanIssueProposal(
                    id: "snap-default-stop-\(tag)-\(nearest.id)",
                    title: "Move “\(nearest.name)” to \(defaultText)",
                    detail: "Changes the \(fromText) stop on \(label) to the fvar default (\(defaultText)). Keeps the stop name.",
                    action: .revalueStop(axisTag: tag, stopID: nearest.id, newValue: defaultValue),
                    isRecommended: preferSnap
                )
            )
        }

        if !axis.values.contains(where: { AxisCoordinate.valuesEqual($0.value, defaultValue) }) {
            let placeholder = AxisValue(id: "preview", value: defaultValue, name: "", elidable: false)
            let name = AxisStopNamingDefaults.suggestedName(for: placeholder, axisTag: tag)
            let preferInsert = proposals.first(where: \.isRecommended) == nil
            proposals.append(
                PlanIssueProposal(
                    id: "add-default-stop-\(tag)",
                    title: "Add stop at \(defaultText)",
                    detail: "Inserts a Format 1 stop at the fvar default on \(label), named “\(name)”.",
                    action: .insertAxisStop(axisTag: tag, value: defaultValue, name: name),
                    isRecommended: preferInsert
                )
            )
        }

        proposals.append(
            PlanIssueProposal(
                id: "keep-default-missing-\(tag)",
                title: "Don't change",
                detail: "Leave \(label) without a stop at the fvar default. The resting instance may be missing from the grid.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning)),
                isRecommended: proposals.isEmpty
            )
        )

        return proposals
    }

    private static func defaultInstanceExcludedProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let key = warning.keys?.first else {
            return acknowledgeOnlyProposals(for: warning)
        }
        return [
            PlanIssueProposal(
                id: "include-default-instance",
                title: "Include default instance",
                detail: "Add the fvar default-coordinate instance to the save plan.",
                action: .includeInstanceKey(key),
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "keep-default-excluded",
                title: "Keep excluded",
                detail: "Leave the default-coordinate instance out of the save plan.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func italConventionProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let stopID = warning.stopIDs?.first,
              let axis = font.axes.first(where: { $0.tag == tag }),
              let stop = axis.values.first(where: { $0.id == stopID }),
              let corrected = RegistrationAxisSupport.correctedItalConventionValue(for: stop) else { return [] }

        if let compound = compoundOrphanItalProposal(
            axisTag: tag,
            stopID: stopID,
            stop: stop,
            font: font,
            warning: warning
        ) {
            return [compound]
        }

        let label = corrected == 0 ? "0 (Roman/upright)" : "1 (Italic)"
        return [
            PlanIssueProposal(
                id: "ital-convention-fix",
                title: "Set value to \(label)",
                detail: "Align “\(stop.name)” with the usual \(tag) convention (\(label)).",
                action: .revalueStop(axisTag: tag, stopID: stopID, newValue: corrected),
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "ital-convention-keep",
                title: "Keep current value",
                detail: "Leave “\(stop.name)” at \(AxisCoordinateFormat.format(stop.value)).",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func defaultTokenNamesProposals(for warning: PlanWarning, font: FontDocument) -> [PlanIssueProposal] {
        applyAxisNeutralsProposals(
            for: warning,
            detail: AxisStopNamingDefaults.applyAxisNeutralsDetail(for: font)
        )
    }

    private static func duplicateComposedNameProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        if AxisStopNamingDefaults.hasInstanceAxisValueConflicts(font) {
            return conflictBlocksNamingFixProposals(for: warning, font: font)
        }
        if AxisStopNamingDefaults.hasUniformStopNamesOnInstanceAxes(font),
           AxisStopNamingDefaults.wouldChangeFromApplyAxisDefaults(font) {
            return applyAxisDefaultsProposals(
                for: warning,
                title: "Rename stops from values",
                detail: AxisStopNamingDefaults.applyAxisDefaultsDetail(for: font)
            )
        }
        if AxisStopNamingDefaults.hasAxisNeutralMismatch(font),
           AxisStopNamingDefaults.wouldChangeFromApplyAxisNeutrals(font) {
            return applyAxisNeutralsProposals(
                for: warning,
                detail: AxisStopNamingDefaults.applyAxisNeutralsDetail(for: font)
            )
        }
        if AxisStopNamingDefaults.wouldChangeFromApplyAxisDefaults(font) {
            return applyAxisDefaultsProposals(
                for: warning,
                title: "Rename stops from values",
                detail: AxisStopNamingDefaults.applyAxisDefaultsDetail(for: font)
            )
        }
        return noAutomaticNamingFixProposals(for: warning)
    }

    private static func conflictBlocksNamingFixProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        let axisTag = warning.axis ?? AxisStopNamingDefaults.axesWithValueConflicts(in: font).first
        return [
            PlanIssueProposal(
                id: "resolve-value-conflicts",
                title: "Resolve value conflicts",
                detail: "Duplicate instance names come from stops sharing the same coordinate. Open the axis conflict resolver to fix values first, then revisit naming.",
                action: .openAxisConflicts(axisTag: axisTag),
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "resolve-value-conflicts-later",
                title: "Not now",
                detail: "Leave this warning for later.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning)),
                isRecommended: false
            ),
        ]
    }

    private static func emptyInstanceAxisProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis,
              let axis = font.axes.first(where: { $0.tag == tag }),
              axis.role == .instance,
              axis.values.isEmpty,
              !axis.isDesignRecordOnly else { return [] }

        let label = axis.displayName ?? tag
        let value = AxisStopSuggestions.suggestedValue(for: axis)
        let valueText = AxisStopSuggestions.formatValue(value)
        let placeholderStop = AxisValue(id: "preview", value: value, name: "", elidable: false)
        let name = AxisStopNamingDefaults.suggestedName(for: placeholderStop, axisTag: tag)

        var proposals: [PlanIssueProposal] = []

        proposals.append(
            PlanIssueProposal(
                id: "empty-axis-add-stop-\(tag)",
                title: "Add a default stop",
                detail: "Adds a stop at \(valueText) named “\(name)” on \(label).",
                action: .insertAxisStop(axisTag: tag, value: value, name: name)
            )
        )

        proposals.append(
            PlanIssueProposal(
                id: "empty-axis-stat-only-\(tag)",
                title: "Switch to STAT-only",
                detail: "Takes \(label) off the instance grid so composed names no longer require stops on this axis.",
                action: .setAxisRole(axisTag: tag, role: .statOnly),
                isRecommended: AxisStopFillPlanner.options(for: axis) == nil
            )
        )

        proposals.append(
            PlanIssueProposal(
                id: "empty-axis-keep-\(tag)",
                title: "Keep as-is",
                detail: "Leave this axis empty on the instance grid.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            )
        )

        return proposals
    }

    private static func noAutomaticNamingFixProposals(for warning: PlanWarning) -> [PlanIssueProposal] {
        [
            PlanIssueProposal(
                id: "no-auto-naming-fix",
                title: "Adjust stops manually",
                detail: "There's no safe one-click rename left for this — stops can be renamed or elided in the axis tree, or Resolve can handle any axis conflicts.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning)),
                isRecommended: false
            ),
        ]
    }

    private static func applyAxisNeutralsProposals(
        for warning: PlanWarning,
        detail: String
    ) -> [PlanIssueProposal] {
        [
            PlanIssueProposal(
                id: "apply-axis-neutrals",
                title: "Align baseline labels",
                detail: detail,
                action: .applyAxisNeutrals,
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "keep-names",
                title: "Keep names",
                detail: "Leave instance names as they are.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func applyAxisDefaultsProposals(
        for warning: PlanWarning,
        title: String = "Apply axis defaults",
        detail: String
    ) -> [PlanIssueProposal] {
        [
            PlanIssueProposal(
                id: "apply-axis-defaults",
                title: title,
                detail: detail,
                action: .applyAxisDefaults,
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "keep-names",
                title: "Keep names",
                detail: "Leave instance names as they are.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func multipleElidableProposals(
        for warning: PlanWarning,
        font: FontDocument
    ) -> [PlanIssueProposal] {
        guard let tag = warning.axis else { return [] }
        let label = font.axes.first(where: { $0.tag == tag })?.displayName ?? tag
        return [
            PlanIssueProposal(
                id: "normalize-elidable-\(tag)",
                title: "Keep one elidable stop",
                detail: "Clear elision on all but the lowest-value stop on \(label).",
                action: .normalizeElidable(axisTag: tag),
                isRecommended: true
            ),
            PlanIssueProposal(
                id: "clear-all-elidable-\(tag)",
                title: "Clear all elision",
                detail: "Turns off elision on every stop on \(label), so composed names won't omit any of them.",
                action: .clearAllElidable(axisTag: tag)
            ),
            PlanIssueProposal(
                id: "keep-elidable-\(tag)",
                title: "Keep as-is",
                detail: "Leave elidable flags unchanged.",
                action: .acknowledgeIssue(issueKey: PlanIssueCodes.issueKey(for: warning))
            ),
        ]
    }

    private static func clearAllElidable(on axisTag: String, font: inout FontDocument) {
        guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
        for index in font.axes[axisIndex].values.indices {
            font.axes[axisIndex].values[index].elidable = false
        }
    }

    private static func normalizeElidable(on axisTag: String, font: inout FontDocument) {
        guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axisTag }) else { return }
        let elidableStops = font.axes[axisIndex].values.filter(\.elidable)
        guard elidableStops.count > 1,
              let keep = elidableStops.min(by: { $0.value < $1.value }) else { return }
        for index in font.axes[axisIndex].values.indices {
            font.axes[axisIndex].values[index].elidable =
                font.axes[axisIndex].values[index].id == keep.id
        }
    }

    private static func compoundOrphanItalProposal(
        axisTag: String,
        stopID: String,
        stop: AxisValue,
        font: FontDocument,
        warning: PlanWarning
    ) -> PlanIssueProposal? {
        guard stop.statFormat == 3,
              let axis = font.axes.first(where: { $0.tag == axisTag }),
              let corrected = RegistrationAxisSupport.correctedItalConventionValue(for: stop) else {
            return nil
        }

        let hasOrphan = StatFormat3Pairing.orphanLinkWarnings(for: axis)
            .contains { $0.stopIDs?.contains(stopID) == true }
        let hasItalMismatch = RegistrationAxisSupport.italConventionWarnings(font: font)
            .contains { $0.stopIDs?.contains(stopID) == true }
        guard hasOrphan && hasItalMismatch else { return nil }

        let romanLabel = corrected == 0 ? "0 (Roman)" : "1 (Italic)"
        var actions: [PlanIssueAction] = [
            .revalueStop(axisTag: axisTag, stopID: stopID, newValue: corrected),
        ]
        if stop.statFormat != 3 || stop.linkedValue == nil {
            actions.append(.updateStopFormat3Link(axisTag: axisTag, stopID: stopID, linkedValue: corrected == 0 ? 1 : 0))
        } else if let linked = stop.linkedValue,
                  !StatFormat3Pairing.isConventionStyleLink(axis: axis, stop: stop, linkedValue: linked) {
            actions.append(.updateStopFormat3Link(axisTag: axisTag, stopID: stopID, linkedValue: corrected == 0 ? 1 : 0))
        }
        if font.fileStatRegistration[axisTag].map({ AxisCoordinate.valuesEqual($0, stop.value) }) == true {
            actions.append(.setFileRegistration(tag: axisTag, value: corrected))
        }

        return PlanIssueProposal(
            id: "compound-orphan-ital-\(stopID)",
            title: "Set value to \(romanLabel) and keep Format 3 link",
            detail: "Align “\(stop.name)” with the usual \(axisTag) convention while preserving style-link semantics.",
            action: .compound(actions),
            isRecommended: true
        )
    }
}

extension StatFormat3Pairing {
    public static func orphanLinkWarnings(axes: [AxisDefinition]) -> [PlanWarning] {
        axes.flatMap { orphanLinkWarnings(for: $0) }
    }
}
