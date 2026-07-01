import SwiftUI
import VarFontCore

private enum ConflictStopTableLayout {
    static let rowHorizontalPadding: CGFloat = 8
    static let valueWidth: CGFloat = 56
    static let nameGap: CGFloat = 12
    static let elidableWidth: CGFloat = 52
}

struct AxisConflictResolverSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let bundle: AxisConflictBundle

    @State private var selectedStopID: String = ""
    @State private var selectedStrategy: ConflictFixStrategy = .remove
    @State private var renameDraft = ""
    @State private var revalueDraft = ""
    @State private var renameUsesSuggestion = true
    @State private var revalueUsesSuggestion = true
    @State private var hoveredStopID: String?

    private var axis: AxisDefinition? {
        editor.selectedFont?.axes.first { $0.tag == bundle.axisTag }
    }

    private var involvedStops: [AxisValue] {
        guard let axis else { return [] }
        return bundle.stops(from: axis).sorted { $0.value < $1.value }
    }

    private var selectedStop: AxisValue? {
        involvedStops.first { $0.id == selectedStopID }
    }

    private var availableStrategies: [ConflictFixStrategy] {
        guard let axis else { return [] }
        return ConflictResolver.strategies(for: bundle, axis: axis)
    }

    private var renameAssumingValue: Double? {
        switch selectedStrategy {
        case .revalueAndRename, .revalueAndSetElidable:
            return resolvedRevalue
        default:
            return nil
        }
    }

    private var resolvedRename: String {
        guard let stop = selectedStop, let axis else { return "" }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || renameUsesSuggestion {
            return ConflictResolver.suggestedRename(
                for: stop,
                bundle: bundle,
                axis: axis,
                assumingValue: renameAssumingValue
            )
        }
        return trimmed
    }

    private var resolvedRevalue: Double? {
        guard let stop = selectedStop, let axis else { return nil }
        if revalueUsesSuggestion {
            return ConflictResolver.suggestedRevalue(
                for: stop,
                axis: axis,
                excludingStopIDs: Set(bundle.involvedStopIDs)
            )
        }
        return ConflictResolver.parseValue(revalueDraft)
    }

    private var resolvedAction: ConflictFixAction? {
        guard let stop = selectedStop, let axis else { return nil }
        return ConflictResolver.resolvedAction(
            strategy: selectedStrategy,
            stop: stop,
            bundle: bundle,
            axis: axis,
            renameText: renameUsesSuggestion ? "" : renameDraft,
            revalueText: revalueUsesSuggestion ? "" : revalueDraft
        )
    }

    private var validationMessage: String? {
        guard let stop = selectedStop, let axis else { return nil }
        switch selectedStrategy {
        case .rename:
            return ConflictResolver.validateRename(resolvedRename, for: stop, axis: axis)
        case .revalue, .revalueAndRename, .revalueAndSetElidable:
            guard let value = resolvedRevalue else { return "Enter a valid number." }
            if let revalueError = ConflictResolver.validateRevalue(
                value,
                for: stop,
                axis: axis,
                excludingStopIDs: Set(bundle.involvedStopIDs)
            ) {
                return revalueError
            }
            if selectedStrategy == .revalueAndRename {
                return ConflictResolver.validateRename(resolvedRename, for: stop, axis: axis)
            }
            return nil
        case .remove, .setElidable:
            return nil
        }
    }

    private var stopOutcomes: [ConflictStopOutcome] {
        guard let axis, let action = resolvedAction else { return [] }
        return ConflictResolver.previewInvolvedStops(
            axis: axis,
            bundle: bundle,
            applying: action
        )
    }

    private var resolvesConflict: Bool {
        guard let action = resolvedAction else { return false }
        return editor.conflictPreview(for: bundle, applying: action)?.resolvesConflict == true
    }

    private var canApply: Bool {
        validationMessage == nil && resolvedAction != nil
    }

    private var applyButtonTitle: String {
        if resolvesConflict {
            return "Apply fix"
        }
        return involvedStops.count > 2 ? "Apply and continue" : "Apply fix"
    }

    private var needsFollowUpPass: Bool {
        involvedStops.count > 2 && !resolvesConflict
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sheetSectionSpacing) {
            header
            stopsSection
            symptomSection
            fixSection
            previewSection
            actions
        }
        .padding(StudioSpacing.sheetOuterPadding)
        .frame(width: 440)
        .onAppear(perform: syncOnAppear)
        .onChange(of: selectedStopID) { _, _ in syncDraftsForSelectedStop() }
        .onChange(of: selectedStrategy) { _, _ in syncDraftsForSelectedStop() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolve axis conflict")
                .font(StudioTypography.emphasis)
            HStack(spacing: 8) {
                StudioTagPill(text: bundle.axisTag)
                Text(bundle.axisLabel)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
                Text(kindLabel)
                    .font(StudioTypography.meta.weight(.medium))
                    .foregroundStyle(StudioColors.warningForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(StudioColors.warningFill, in: Capsule())
            }
        }
    }

    private var kindLabel: String {
        switch bundle.kind {
        case .duplicateValue: "Duplicate value"
        case .duplicateName: "Duplicate name"
        case .duplicateValueAndName: "Duplicate value and name"
        }
    }

    @ViewBuilder
    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select the stop to change")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
                stopTableHeader

                ForEach(involvedStops) { stop in
                    selectableStopRow(stop)
                }
            }
            .padding(.vertical, 8)
            .background(StudioColors.surfaceMuted, in: RoundedRectangle(cornerRadius: StudioRadius.chip))
        }
    }

    private var stopTableHeader: some View {
        HStack(spacing: 0) {
            Text("Value")
                .frame(width: ConflictStopTableLayout.valueWidth, alignment: .trailing)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ConflictStopTableLayout.nameGap)
            Text("Elidable")
                .frame(width: ConflictStopTableLayout.elidableWidth, alignment: .center)
        }
        .font(StudioTypography.columnLabel)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, ConflictStopTableLayout.rowHorizontalPadding)
        .padding(.bottom, 2)
    }

    private func selectableStopRow(_ stop: AxisValue) -> some View {
        let isSelected = stop.id == selectedStopID
        let isHovered = stop.id == hoveredStopID

        return Button {
            selectedStopID = stop.id
        } label: {
            HStack(spacing: 0) {
                Text(AxisStopSuggestions.formatValue(stop.value))
                    .font(StudioTypography.monoValue)
                    .foregroundStyle(StudioColors.axisValue)
                    .frame(width: ConflictStopTableLayout.valueWidth, alignment: .trailing)

                Text(stop.name)
                    .font(StudioTypography.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, ConflictStopTableLayout.nameGap)

                ConflictElidableIndicator(isOn: stop.elidable)
                    .frame(width: ConflictStopTableLayout.elidableWidth)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, ConflictStopTableLayout.rowHorizontalPadding)
            .background {
                StudioRowBackground(
                    isSelected: isSelected,
                    isHovered: isHovered
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: StudioRadius.row))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredStopID = hovering ? stop.id : (hoveredStopID == stop.id ? nil : hoveredStopID)
        }
    }

    @ViewBuilder
    private var symptomSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if involvedStops.count > 2 {
                Text("\(involvedStops.count) stops conflict on this axis. Fix one stop at a time.")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary = bundle.symptomSummary {
                Text(summary)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var fixSection: some View {
        if selectedStop != nil, !availableStrategies.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("How should this stop be fixed?")
                    .font(StudioTypography.sectionLabel)
                    .foregroundStyle(.secondary)

                Picker("Fix", selection: $selectedStrategy) {
                    ForEach(availableStrategies) { strategy in
                        Text(ConflictResolver.strategyLabel(strategy)).tag(strategy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                if let stop = selectedStop, let axis {
                    Text(ConflictResolver.strategyDetail(
                        strategy: selectedStrategy,
                        stop: stop,
                        axis: axis,
                        bundle: bundle
                    ))
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    strategyFields(stop: stop, axis: axis)
                }
            }
        }
    }

    @ViewBuilder
    private func strategyFields(stop: AxisValue, axis: AxisDefinition) -> some View {
        if showsRevalueFields {
            revalueFields(stop: stop, axis: axis)
        }
        if showsRenameFields {
            renameFields(stop: stop, axis: axis)
        }

        if let validationMessage {
            Text(validationMessage)
                .font(StudioTypography.caption)
                .foregroundStyle(.red)
        }
    }

    private var showsRevalueFields: Bool {
        switch selectedStrategy {
        case .revalue, .revalueAndRename, .revalueAndSetElidable:
            return true
        default:
            return false
        }
    }

    private var showsRenameFields: Bool {
        switch selectedStrategy {
        case .rename, .revalueAndRename:
            return true
        default:
            return false
        }
    }

    private func renameFields(stop: AxisValue, axis: AxisDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New name")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
            StudioTextField(
                placeholder: ConflictResolver.suggestedRename(
                    for: stop,
                    bundle: bundle,
                    axis: axis,
                    assumingValue: renameAssumingValue
                ),
                text: $renameDraft
            )
            .onChange(of: renameDraft) { _, text in
                renameUsesSuggestion = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            Text("Suggested: “\(resolvedRename)”")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
        }
    }

    private func revalueFields(stop: AxisValue, axis: AxisDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New value")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
            StudioTextField(
                placeholder: AxisStopSuggestions.formatValue(
                    ConflictResolver.suggestedRevalue(
                        for: stop,
                        axis: axis,
                        excludingStopIDs: Set(bundle.involvedStopIDs)
                    )
                ),
                text: $revalueDraft,
                font: StudioTypography.monoValue
            )
            .onChange(of: revalueDraft) { _, text in
                revalueUsesSuggestion = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let min = axis.min, let max = axis.max {
                Text("Allowed \(AxisStopSuggestions.formatValue(min)) – \(AxisStopSuggestions.formatValue(max))")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !stopOutcomes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Result")
                    .font(StudioTypography.sectionLabel)
                    .foregroundStyle(.secondary)

                VStack(spacing: 2) {
                    stopTableHeader

                    ForEach(stopOutcomes) { outcome in
                        outcomeRow(outcome)
                    }
                }
                .padding(.vertical, 8)
                .background(StudioColors.surfaceMuted, in: RoundedRectangle(cornerRadius: StudioRadius.chip))
                .overlay {
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .strokeBorder(
                            resolvesConflict ? StudioColors.successStroke : StudioColors.warningStroke,
                            lineWidth: 0.5
                        )
                }

                if resolvesConflict {
                    Label("This fix clears the axis conflict", systemImage: "checkmark.circle.fill")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.green)
                } else if needsFollowUpPass {
                    Label(
                        "One step done — apply to continue with the remaining stops",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(StudioTypography.caption)
                    .foregroundStyle(StudioColors.warningForeground)
                } else {
                    Label("Conflict may remain after this fix", systemImage: "exclamationmark.triangle.fill")
                        .font(StudioTypography.caption)
                        .foregroundStyle(StudioColors.warningForeground)
                }
            }
        }
    }

    private func outcomeRow(_ outcome: ConflictStopOutcome) -> some View {
        HStack(spacing: 0) {
            outcomeValueCell(outcome)
                .frame(width: ConflictStopTableLayout.valueWidth, alignment: .trailing)

            outcomeNameCell(outcome)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ConflictStopTableLayout.nameGap)

            ConflictElidableIndicator(
                isOn: outcome.isRemoved ? outcome.elidableBefore : (outcome.elidableAfter ?? false),
                changed: elidableChanged(outcome)
            )
            .frame(width: ConflictStopTableLayout.elidableWidth)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, ConflictStopTableLayout.rowHorizontalPadding)
        .opacity(outcome.isRemoved ? 0.55 : 1)
        .overlay(alignment: .leading) {
            if outcome.isTarget {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func outcomeValueCell(_ outcome: ConflictStopOutcome) -> some View {
        if outcome.isRemoved {
            Text(AxisStopSuggestions.formatValue(outcome.valueBefore))
                .font(StudioTypography.monoValue)
                .foregroundStyle(.secondary)
                .strikethrough()
        } else if valueChanged(outcome), let after = outcome.valueAfter {
            HStack(spacing: 4) {
                Text(AxisStopSuggestions.formatValue(outcome.valueBefore))
                    .foregroundStyle(.secondary)
                Text("→")
                    .foregroundStyle(.tertiary)
                Text(AxisStopSuggestions.formatValue(after))
                    .foregroundStyle(StudioColors.axisValue)
            }
            .font(StudioTypography.monoValue)
        } else {
            Text(AxisStopSuggestions.formatValue(outcome.valueBefore))
                .font(StudioTypography.monoValue)
                .foregroundStyle(StudioColors.axisValue)
        }
    }

    @ViewBuilder
    private func outcomeNameCell(_ outcome: ConflictStopOutcome) -> some View {
        if outcome.isRemoved {
            HStack(spacing: 6) {
                Text(outcome.nameBefore)
                    .strikethrough()
                Text("Removed")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
            }
            .font(StudioTypography.body)
            .foregroundStyle(.secondary)
        } else if nameChanged(outcome), let after = outcome.nameAfter {
            HStack(spacing: 4) {
                Text(outcome.nameBefore)
                    .foregroundStyle(.secondary)
                Text("→")
                    .foregroundStyle(.tertiary)
                Text(after)
                    .foregroundStyle(.primary)
            }
            .font(StudioTypography.body)
        } else {
            Text(outcome.nameBefore)
                .font(StudioTypography.body)
                .foregroundStyle(.primary)
        }
    }

    private func valueChanged(_ outcome: ConflictStopOutcome) -> Bool {
        guard let after = outcome.valueAfter else { return false }
        return !AxisCoordinate.valuesEqual(outcome.valueBefore, after)
    }

    private func nameChanged(_ outcome: ConflictStopOutcome) -> Bool {
        guard let after = outcome.nameAfter else { return false }
        return outcome.nameBefore != after
    }

    private func elidableChanged(_ outcome: ConflictStopOutcome) -> Bool {
        guard let after = outcome.elidableAfter else { return false }
        return outcome.elidableBefore != after
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                editor.dismissConflictResolver()
                dismiss()
            }
            Button(applyButtonTitle) {
                guard let action = resolvedAction else { return }
                editor.applyConflictFix(action, axisTag: bundle.axisTag)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
        .padding(.top, 4)
    }

    // MARK: - State

    private func syncOnAppear() {
        selectedStopID = involvedStops.first?.id ?? ""
        selectedStrategy = defaultStrategy
        syncDraftsForSelectedStop()
    }

    private var defaultStrategy: ConflictFixStrategy {
        switch bundle.kind {
        case .duplicateName:
            return .rename
        case .duplicateValue:
            return .remove
        case .duplicateValueAndName:
            return .revalueAndRename
        }
    }

    private func syncDraftsForSelectedStop() {
        guard selectedStop != nil else { return }
        renameDraft = ""
        revalueDraft = ""
        renameUsesSuggestion = true
        revalueUsesSuggestion = true
        if !availableStrategies.contains(selectedStrategy) {
            selectedStrategy = availableStrategies.first ?? .remove
        }
    }
}

private struct ConflictElidableIndicator: View {
    let isOn: Bool
    var changed: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    changed ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.35),
                    lineWidth: 1
                )
                .frame(width: 12, height: 12)
            if isOn {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel(isOn ? "Elidable" : "Not elidable")
    }
}
