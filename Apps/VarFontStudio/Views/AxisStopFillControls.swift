import SwiftUI
import VarFontCore

/// Shared "evenly spaced" / "every N units" controls for quick-filling axis stops.
///
/// Used by both the plan-issue resolver (fixing an empty instance axis) and the axis tree's
/// standalone "Fill stops…" tool. The axis tree tool can be reopened anytime to tweak a fill —
/// it replaces the axis's stops rather than requiring the axis to start empty, so there's no
/// need to undo before trying a different count or interval.
struct AxisStopFillControls: View {
    let axis: AxisDefinition
    let options: AxisStopFillOptions
    @Binding var fillMode: AxisStopFillMode
    @Binding var stopCount: Double
    @Binding var intervalStep: Double

    var values: [Double]? {
        switch fillMode {
        case .evenCount:
            return AxisStopFillPlanner.values(for: axis, count: Int(stopCount.rounded()))
        case .fixedInterval:
            return AxisStopFillPlanner.values(for: axis, interval: intervalStep)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            Picker("Fill mode", selection: $fillMode) {
                Text("Evenly spaced").tag(AxisStopFillMode.evenCount)
                Text("Every N units").tag(AxisStopFillMode.fixedInterval)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch fillMode {
            case .evenCount:
                evenCountControls
            case .fixedInterval:
                intervalControls
            }

            if let values, !values.isEmpty {
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

    private var evenCountControls: some View {
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
                    countChip(count, enabled: options.recommendedCounts.contains(count))
                }
            }
        }
    }

    private func countChip(_ count: Int, enabled: Bool) -> some View {
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

    private var intervalControls: some View {
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
                step: intervalSliderStep
            )

            if let values {
                Text(
                    "Produces \(values.count) stop\(values.count == 1 ? "" : "s") across "
                        + "\(AxisStopSuggestions.formatValue(options.minValue))–\(AxisStopSuggestions.formatValue(options.maxValue))."
                )
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var intervalSliderStep: Double {
        let span = options.intervalRange.upperBound - options.intervalRange.lowerBound
        if span <= 10 { return 0.1 }
        if span <= 100 { return 1 }
        if span <= 1_000 { return 5 }
        return 10
    }
}
