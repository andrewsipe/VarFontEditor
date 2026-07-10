import Foundation

public enum InstancePlanner {
    public struct Options: Sendable {
        public var detectDuplicates: Bool

        public init(detectDuplicates: Bool = true) {
            self.detectDuplicates = detectDuplicates
        }
    }

    public static func plan(
        font: FontDocument,
        naming: NamingPolicy,
        options: Options = Options()
    ) -> InstancePlan {
        let gridAxes = font.axes.filter { $0.role == .instance }
        let formulaParts = gridAxes.map(\.values.count)
        let generated = cartesianProduct(gridAxes: gridAxes)
        let excluded = Set(font.excludedInstanceKeys)
        let includedWhitelist = Set(font.includedInstanceKeys)

        var warnings = validateAxes(font.axes)
        warnings.append(contentsOf: AxisStopValidator.validate(axes: font.axes))
        warnings.append(contentsOf: validateInstanceKeySets(font))
        warnings.append(contentsOf: validateClarifiers(font: font))
        warnings.append(contentsOf: RegistrationAxisSupport.allRegistrationPlanWarnings(font: font, analysis: nil))
        warnings.append(contentsOf: validateCompoundStatValues(font))
        var instances: [PlannedInstance] = []
        var seenComposedNames: Set<String> = []

        let pinned = AxisPinPolicy.pinnedCoords(from: font.axes)

        for var coords in generated {
            for (tag, value) in pinned where coords[tag] == nil {
                coords[tag] = value
            }
            let key = InstanceKeyBuilder.makeKey(coords: coords)
            let composed = NamingComposer.compose(
                coords: coords,
                axes: font.axes,
                naming: naming,
                fileRole: font.fileRole,
                fileStatRegistration: font.fileStatRegistration
            )
            let chain = composed.chain.map {
                NamingChainLink(kind: $0.kind, tag: $0.tag, name: $0.name, elided: $0.elided)
            }

            let included: Bool
            if !includedWhitelist.isEmpty {
                included = includedWhitelist.contains(key)
            } else {
                included = !excluded.contains(key)
            }

            let duplicate = options.detectDuplicates && !seenComposedNames.insert(composed.name).inserted

            instances.append(
                PlannedInstance(
                    key: key,
                    composedName: composed.name,
                    coords: coords,
                    included: included,
                    duplicate: duplicate,
                    namingChain: chain
                )
            )
        }

        markAllDuplicateComposedNames(in: &instances)

        if options.detectDuplicates {
            warnings.append(
                contentsOf: ComposedNameWarningRollup.warnings(
                    instances: instances,
                    axes: font.axes,
                    naming: naming
                )
            )
        }
        if let neutralMismatchWarning = validateAxisNeutralMismatch(font: font) {
            warnings.append(neutralMismatchWarning)
        }
        if let defaultTokenWarning = validateDefaultTokenNames(instances: instances, naming: naming) {
            warnings.append(defaultTokenWarning)
        }
        warnings.append(
            contentsOf: OpenTypeAxisAudit.planWarnings(
                font: font,
                instances: instances,
                namingOrder: naming.order
            )
        )
        warnings = warnings.filter {
            !font.dismissedPlanIssues.contains(PlanIssueCodes.issueKey(for: $0))
        }

        let totalGenerated = instances.count
        let totalIncluded = instances.filter(\.included).count

        return InstancePlan(
            schemaVersion: 1,
            fontID: font.id,
            formula: PlanFormula(
                parts: formulaParts,
                totalGenerated: totalGenerated,
                totalIncluded: totalIncluded,
                totalExcluded: totalGenerated - totalIncluded
            ),
            instances: instances,
            warnings: warnings,
            namePlanSummary: nil
        )
    }

    public static func plan(project: ProjectDocument, fontID: String, options: Options = Options()) -> InstancePlan? {
        guard let font = project.fonts.first(where: { $0.id == fontID }) else { return nil }
        return plan(font: font, naming: project.naming, options: options)
    }

    // MARK: - Private

    private static func cartesianProduct(gridAxes: [AxisDefinition]) -> [[String: Double]] {
        guard !gridAxes.isEmpty else { return [] }
        var results: [[String: Double]] = [ [:] ]
        for axis in gridAxes {
            var next: [[String: Double]] = []
            for partial in results {
                for stop in axis.values {
                    var coords = partial
                    coords[axis.tag] = stop.value
                    next.append(coords)
                }
            }
            results = next
        }
        return results
    }

    private static func validateAxes(_ axes: [AxisDefinition]) -> [PlanWarning] {
        var warnings: [PlanWarning] = []
        for axis in axes {
            let elidable = axis.values.filter(\.elidable)
            if elidable.count > 1 {
                warnings.append(
                    PlanWarning(
                        code: "multiple_elidable",
                        axis: axis.tag,
                        stopIDs: elidable.map(\.id),
                        message: "Axis '\(axis.tag)' has \(elidable.count) elidable stops; at most one is allowed.",
                        hint: "Only one stop per axis can be elidable — clear it on the rest."
                    )
                )
            }
            if axis.role == .instance, axis.values.isEmpty {
                warnings.append(
                    PlanWarning(
                        code: "empty_instance_axis",
                        axis: axis.tag,
                        message: "Instance axis '\(axis.tag)' has no stops.",
                        hint: "This axis needs at least one stop, or it can be switched off as an instance axis."
                    )
                )
            }
        }
        return warnings
    }

    private static func markAllDuplicateComposedNames(in instances: inout [PlannedInstance]) {
        var counts: [String: Int] = [:]
        for instance in instances {
            counts[instance.composedName, default: 0] += 1
        }
        for index in instances.indices {
            if counts[instances[index].composedName, default: 0] > 1 {
                instances[index].duplicate = true
            }
        }
    }

    private static func validateClarifiers(font: FontDocument) -> [PlanWarning] {
        guard let role = font.fileRole else { return [] }
        var warnings: [PlanWarning] = []

        let categories = role.clarifiers.map(\.category)
        let unique = Set(categories)
        if unique.count != categories.count {
            warnings.append(
                PlanWarning(
                    code: "duplicate_clarifier_category",
                    message: "This file has more than one clarifier in the same category.",
                    hint: "Each clarifier category (slope, width, optical, custom) works best with just one label."
                )
            )
        }

        for clarifier in role.clarifiers {
            let axisTag: String? = switch clarifier.category {
            case .slope:
                if font.axes.contains(where: { $0.tag == "ital" }) {
                    "ital"
                } else if font.axes.contains(where: { $0.tag == "slnt" }) {
                    "slnt"
                } else {
                    nil
                }
            case .width: "wdth"
            case .optical: "opsz"
            case .custom: nil
            }
            if let axisTag,
               let axis = font.axes.first(where: { $0.tag == axisTag }),
               axis.role == .instance,
               !axis.values.isEmpty {
                warnings.append(
                    PlanWarning(
                        code: "clarifier_axis_overlap",
                        axis: axisTag,
                        name: clarifier.label,
                        message: "File clarifier '\(clarifier.label)' (\(clarifier.category.rawValue)) overlaps with instance axis '\(axisTag)'.",
                        hint: "If width/slope/optical actually varies inside this file, the clarifier can go, or the axis can switch to STAT-only."
                    )
                )
            }
        }

        return warnings
    }

    private static func validateCompoundStatValues(_ font: FontDocument) -> [PlanWarning] {
        let axisTags = Set(font.axes.map(\.tag))
        return font.compoundStatValues.compactMap { compound in
            let missing = compound.coords.keys.filter { !axisTags.contains($0) }
            guard !missing.isEmpty else { return nil }
            return PlanWarning(
                code: "compound_axis_missing",
                name: compound.name,
                message: "Combination style “\(compound.name)” references missing axis tag(s): \(missing.sorted().joined(separator: ", ")).",
                hint: "This leg is orphaned — remove it, or restore the axis, before saving."
            )
        }
    }

    private static func validateAxisNeutralMismatch(font: FontDocument) -> PlanWarning? {
        let message = AxisStopNamingDefaults.axisNeutralMismatchWarningMessage(for: font)
        guard !message.isEmpty else { return nil }
        return PlanWarning(
            code: "axis_neutral_mismatch",
            message: message,
            hint: "Renaming aligns stop labels with how this tool builds composed instance names."
        )
    }

    private static func validateDefaultTokenNames(
        instances: [PlannedInstance],
        naming: NamingPolicy
    ) -> PlanWarning? {
        let included = instances.filter(\.included)
        guard !included.isEmpty else { return nil }
        let hasDuplicateComposed = Set(included.map(\.composedName)).count < included.count
        guard !hasDuplicateComposed else { return nil }
        guard included.allSatisfy({
            AxisStopNamingDefaults.composedNameUsesOnlyDefaultTokens($0.composedName, elidedFallback: naming.elidedFallback)
        }) else { return nil }

        return PlanWarning(
            code: "default_token_names",
            message: "Instance names are only default labels (e.g. “\(included[0].composedName)”).",
            hint: "Applying standard axis labels lets the baseline collapse to the elided fallback."
        )
    }

    private static func validateInstanceKeySets(_ font: FontDocument) -> [PlanWarning] {
        let overlap = Set(font.includedInstanceKeys).intersection(font.excludedInstanceKeys)
        guard !overlap.isEmpty else { return [] }
        return [
            PlanWarning(
                code: "conflicting_instance_keys",
                axis: nil,
                name: nil,
                keys: Array(overlap).sorted(),
                message: "\(overlap.count) instance key(s) appear in both included and excluded lists."
            ),
        ]
    }
}
