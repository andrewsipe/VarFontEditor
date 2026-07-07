import SwiftUI
import VarFontCore

private enum ResolverFixSelection: Equatable {
    case interactiveFill
    case proposal(String)
}

struct PlanIssueResolverSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let warning: PlanWarning
    let reviewPosition: Int?
    let reviewTotal: Int?

    @State private var fixSelection: ResolverFixSelection = .interactiveFill
    @State private var fillMode: AxisStopFillMode = .evenCount
    @State private var stopCount: Double = 6
    @State private var intervalStep: Double = 1

    private var proposals: [PlanIssueProposal] {
        editor.planIssueProposals(for: warning)
    }

    private var axis: AxisDefinition? {
        guard let tag = warning.axis else { return nil }
        return editor.selectedFont?.axes.first { $0.tag == tag }
    }

    private var fillOptions: AxisStopFillOptions? {
        guard warning.code == "empty_instance_axis", let axis else { return nil }
        return AxisStopFillPlanner.options(for: axis)
    }

    private var selectedProposal: PlanIssueProposal? {
        guard case .proposal(let id) = fixSelection else { return nil }
        return proposals.first { $0.id == id }
    }

    private var interactiveValues: [Double]? {
        guard let axis, fillOptions != nil else { return nil }
        switch fillMode {
        case .evenCount:
            return AxisStopFillPlanner.values(for: axis, count: Int(stopCount.rounded()))
        case .fixedInterval:
            return AxisStopFillPlanner.values(for: axis, interval: intervalStep)
        }
    }

    private var canApplyInteractiveFill: Bool {
        guard fillOptions != nil, case .interactiveFill = fixSelection else { return false }
        return (interactiveValues?.count ?? 0) >= AxisStopFillPlanner.minStopCount
    }

    private var canApply: Bool {
        if canApplyInteractiveFill { return true }
        return selectedProposal != nil
    }

    private var showsContinue: Bool {
        reviewPosition != nil && reviewTotal != nil && (reviewTotal ?? 0) > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sheetSectionSpacing) {
            header
            warningSection

            if let fillOptions {
                interactiveFillSection(fillOptions)
            }

            if !proposals.isEmpty {
                fallbackSection
            }

            actionBar
        }
        .padding(StudioSpacing.sheetOuterPadding)
        .frame(minWidth: 460)
        .onAppear(perform: configureDefaults)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plan issue")
                .font(StudioTypography.emphasis)
            if let reviewPosition, let reviewTotal {
                Text("Issue \(reviewPosition) of \(reviewTotal)")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
            Text(warning.message)
                .font(StudioTypography.body)
            if let hint = warning.hint {
                Text(hint)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func interactiveFillSection(_ options: AxisStopFillOptions) -> some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            selectableHeader(
                title: "Quick fill stops",
                isSelected: fixSelection == .interactiveFill,
                isRecommended: true
            ) {
                fixSelection = .interactiveFill
            }

            if fixSelection == .interactiveFill {
                Picker("Fill mode", selection: $fillMode) {
                    Text("Evenly spaced").tag(AxisStopFillMode.evenCount)
                    Text("Every N units").tag(AxisStopFillMode.fixedInterval)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch fillMode {
                case .evenCount:
                    evenCountControls(options)
                case .fixedInterval:
                    intervalControls(options)
                }

                if let values = interactiveValues, !values.isEmpty {
                    Text("\(values.count) stops: \(AxisStopFillPlanner.previewLabel(for: values))")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Adjust the slider to get at least \(AxisStopFillPlanner.minStopCount) stops.")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Each stop uses its numeric value as the name.")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            fixSelection == .interactiveFill ? StudioColors.surfaceMuted : Color.clear,
            in: RoundedRectangle(cornerRadius: StudioRadius.row)
        )
    }

    private func evenCountControls(_ options: AxisStopFillOptions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stop count")
                    .font(StudioTypography.caption)
                Spacer()
                Text("\(Int(stopCount.rounded()))")
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $stopCount,
                in: Double(options.countRange.lowerBound)...Double(options.countRange.upperBound),
                step: 1
            )

            HStack(spacing: 6) {
                Text("Suggested")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
                ForEach(AxisStopFillPlanner.suggestedCounts, id: \.self) { count in
                    countChip(count, enabled: options.recommendedCounts.contains(count), options: options)
                }
            }
        }
    }

    private func countChip(_ count: Int, enabled: Bool, options: AxisStopFillOptions) -> some View {
        let isSelected = Int(stopCount.rounded()) == count
        return Button {
            stopCount = Double(count)
        } label: {
            Text("\(count)")
                .font(StudioTypography.meta)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(enabled ? .primary : .tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func intervalControls(_ options: AxisStopFillOptions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step size")
                    .font(StudioTypography.caption)
                Spacer()
                Text(AxisStopSuggestions.formatValue(intervalStep))
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $intervalStep,
                in: options.intervalRange,
                step: intervalSliderStep(for: options)
            )

            if let values = interactiveValues {
                Text("Produces \(values.count) stop\(values.count == 1 ? "" : "s") across \(AxisStopSuggestions.formatValue(options.minValue))–\(AxisStopSuggestions.formatValue(options.maxValue)).")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fallbackSection: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            Text(fillOptions == nil ? "Choose a fix" : "Other options")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)

            ForEach(proposals) { proposal in
                proposalRow(proposal)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                editor.dismissPlanIssueResolver()
                dismiss()
            }
            if showsContinue {
                Button("Apply & continue") {
                    applySelected(andContinue: true)
                }
                .disabled(!canApply)
            }
            Button("Apply") {
                applySelected(andContinue: false)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
    }

    // MARK: - Rows

    private func selectableHeader(
        title: String,
        isSelected: Bool,
        isRecommended: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(StudioTypography.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
                    .font(StudioTypography.bodyMedium)
                    .foregroundStyle(.primary)
                if isRecommended {
                    Text("Recommended")
                        .font(StudioTypography.meta)
                        .foregroundStyle(StudioColors.registrationForeground)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func proposalRow(_ proposal: PlanIssueProposal) -> some View {
        let isSelected = fixSelection == .proposal(proposal.id)
        return Button {
            fixSelection = .proposal(proposal.id)
        } label: {
            HStack(alignment: .top, spacing: StudioSpacing.controlGap) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(StudioTypography.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(proposal.title)
                            .font(StudioTypography.bodyMedium)
                            .foregroundStyle(.primary)
                        if proposal.isRecommended {
                            Text("Recommended")
                                .font(StudioTypography.meta)
                                .foregroundStyle(StudioColors.registrationForeground)
                        }
                    }
                    Text(proposal.detail)
                        .font(StudioTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? StudioColors.surfaceMuted : Color.clear,
            in: RoundedRectangle(cornerRadius: StudioRadius.row)
        )
    }

    // MARK: - Actions

    private func configureDefaults() {
        guard let options = fillOptions else {
            if let recommended = proposals.first(where: \.isRecommended) {
                fixSelection = .proposal(recommended.id)
            } else if let first = proposals.first {
                fixSelection = .proposal(first.id)
            }
            return
        }

        fixSelection = .interactiveFill
        fillMode = .evenCount
        stopCount = Double(options.defaultCount)
        intervalStep = options.defaultInterval
    }

    private func applySelected(andContinue: Bool) {
        if canApplyInteractiveFill,
           let values = interactiveValues,
           let tag = warning.axis {
            editor.applyPlanIssueFix(.insertAxisStops(axisTag: tag, values: values), andContinue: andContinue)
            if !andContinue { dismiss() }
            return
        }

        guard let proposal = selectedProposal else { return }
        editor.applyPlanIssueFix(proposal.action, andContinue: andContinue)
        if !andContinue { dismiss() }
    }

    private func intervalSliderStep(for options: AxisStopFillOptions) -> Double {
        let span = options.intervalRange.upperBound - options.intervalRange.lowerBound
        if span <= 10 { return 0.1 }
        if span <= 100 { return 1 }
        if span <= 1_000 { return 5 }
        return 10
    }
}
