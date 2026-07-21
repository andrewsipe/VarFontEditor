import SwiftUI
import VarFontCore

// MARK: - Axis header

struct AxisTreeAxisHeader: View {
    let axis: AxisDefinition
    let isExpanded: Bool
    var hasConflict: Bool = false
    var axisWarnings: [PlanWarning] = []
    var resolvablePlanWarnings: [PlanWarning] = []
    var fileRegistrationLabel: String?
    var registrationStops: [AxisValue] = []
    var selectedRegistrationStopID: String?
    var onSelectRegistrationStop: ((String) -> Void)?
    @Binding var isInstanceAxis: Bool
    let onToggleExpansion: () -> Void
    var onResolveConflict: (() -> Void)?
    var onReviewPlanIssue: (() -> Void)?
    /// When set, shows a pencil to rename the STAT/fvar axis display name (not the 4-char tag).
    var onUpdateDisplayName: ((String) -> Void)? = nil

    @State private var isEditingDisplayName = false
    @State private var editedDisplayName = ""
    @FocusState private var displayNameFieldFocused: Bool

    private var lane: AxisLane { axis.lane }

    private var currentDisplayName: String {
        axis.displayName ?? axis.tag
    }

    private var hasAxisAttention: Bool {
        hasConflict || !axisWarnings.isEmpty
    }

    private var subtitleText: String? {
        var parts: [String] = []
        switch lane {
        case .variation:
            if let range = axisRangeText { parts.append(range) }
        case .pinned:
            if let range = axisRangeText, let pin = axis.pinCoordinate {
                parts.append("\(range) · Pinned at \(StudioFormatting.axisValue(pin))")
            } else if let pin = axis.pinCoordinate {
                parts.append("Pinned at \(StudioFormatting.axisValue(pin))")
            } else if let range = axisRangeText {
                parts.append(range)
            }
        case .registration:
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var selectedRegistrationName: String {
        if let selectedRegistrationStopID,
           let stop = registrationStops.first(where: { $0.id == selectedRegistrationStopID }) {
            return stop.name
        }
        return fileRegistrationLabel ?? "—"
    }

    private var attentionHelp: String {
        if hasConflict {
            return "Naming conflict on this axis"
        }
        return axisWarnings.map { warning in
            if let hint = warning.hint, !hint.isEmpty {
                return "\(warning.message)\n\(hint)"
            }
            return warning.message
        }.joined(separator: "\n\n")
    }

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            if hasAxisAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(StudioTypography.meta)
                    .foregroundStyle(StudioColors.warningForeground)
                    .help(attentionHelp)
            }

            StudioTagPill(
                text: axis.tag,
                role: axis.isDesignRecordOnly ? .registration : .instance
            )
            .frame(width: AxisBlockLayout.tagColumnWidth, alignment: .leading)

            if axis.fvarHidden {
                Text("hidden")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, StudioSpacing.tightGap)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help("Hide this axis from user-facing controls (fvar HIDDEN_AXIS flag).")
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: StudioSpacing.tightGap) {
                    if isEditingDisplayName {
                        StudioTextField(
                            placeholder: "Axis name",
                            text: $editedDisplayName,
                            font: StudioTypography.body,
                            rowHeight: StudioFieldMetrics.bodyMediumRowHeight,
                            onSubmit: commitDisplayName,
                            onCancel: cancelDisplayName
                        )
                        .focused($displayNameFieldFocused)
                        .frame(maxWidth: 220, alignment: .leading)
                    } else {
                        Button(action: onToggleExpansion) {
                            Text(currentDisplayName)
                                .font(StudioTypography.body)
                                .lineLimit(1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(lane == .registration
                            ? "Naming axis — no fvar scale; this file’s stop is shown beside the label"
                            : "Expand axis stops")
                    }

                    if onUpdateDisplayName != nil, !isEditingDisplayName {
                        StudioToolbarIconButton(
                            systemName: "pencil.circle",
                            help: "Rename axis (STAT and fvar label). The 4-character tag and interpolation are unchanged."
                        ) {
                            editedDisplayName = currentDisplayName
                            isEditingDisplayName = true
                        }
                    }

                    Button(action: onToggleExpansion) {
                        StudioDisclosureChevron(isExpanded: isExpanded)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse axis stops" : "Expand axis stops")

                    Spacer(minLength: 0)
                }
                .onChange(of: isEditingDisplayName) { _, editing in
                    if editing {
                        DispatchQueue.main.async {
                            displayNameFieldFocused = true
                        }
                    }
                }
                .onChange(of: axis.displayName) { _, _ in
                    if !isEditingDisplayName {
                        editedDisplayName = currentDisplayName
                    }
                }

                // File-axis stop menu must stay outside the expand button.
                if lane == .registration {
                    registrationSubtitle
                } else if let subtitleText {
                    Text(subtitleText)
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("The lowest and highest values this axis supports, and its default (fvar min/default/max). D icon = default coordinate.")
                }
            }

            Spacer(minLength: 0)

            if hasConflict, let onResolveConflict {
                Button("Resolve", action: onResolveConflict)
                    .font(StudioTypography.meta)
                    .controlSize(.small)
                    .help("Open conflict resolver for this axis")
            } else if !resolvablePlanWarnings.isEmpty, let onReviewPlanIssue {
                Button("Review…", action: onReviewPlanIssue)
                    .font(StudioTypography.meta)
                    .controlSize(.small)
                    .help(resolvablePlanWarnings.first?.hint ?? "Review plan issues on this axis")
            }

            HStack(spacing: StudioSpacing.rowGap) {
                stopCountBadge
                    .fixedSize(horizontal: true, vertical: false)

                if lane != .registration {
                    Toggle("Instance axis", isOn: $isInstanceAxis)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help(
                            "When on, stops on this axis generate named instances. "
                                + "When off, the axis stays at its default for every instance. "
                                + "Naming axes never use this toggle."
                        )
                        .accessibilityLabel("Instance axis")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var registrationSubtitle: some View {
        HStack(spacing: StudioSpacing.tightGap) {
            Text("No fvar scale")
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)

            if !registrationStops.isEmpty {
                Text("·")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)

                // Single stop: static label (no menu chrome). Multiple: one chevron only.
                if registrationStops.count == 1 || onSelectRegistrationStop == nil {
                    Text(selectedRegistrationName)
                        .font(StudioTypography.meta)
                        .fontWeight(.medium)
                        .foregroundStyle(StudioColors.registrationForeground)
                        .help(registrationStopHelp)
                } else if let onSelectRegistrationStop {
                    Menu {
                        ForEach(registrationStops) { stop in
                            Button {
                                onSelectRegistrationStop(stop.id)
                            } label: {
                                if stop.id == selectedRegistrationStopID {
                                    Label(stop.name, systemImage: "checkmark")
                                } else {
                                    Text(stop.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(selectedRegistrationName)
                                .font(StudioTypography.meta)
                                .fontWeight(.medium)
                                .foregroundStyle(StudioColors.registrationForeground)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(StudioTypography.iconGlyph)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help(registrationStopHelp)
                }
            }
        }
    }

    private var registrationStopHelp: String {
        "This file’s identity on this axis — used in every instance name, not the instance grid."
    }

    private var stopCountBadge: some View {
        let count: Int
        let help: String
        let highlighted: Bool
        switch lane {
        case .registration:
            count = axis.values.count
            help = "\(count) STAT axis value\(count == 1 ? "" : "s") on this design axis"
            highlighted = count > 0
        case .variation:
            count = isInstanceAxis ? axis.values.count : 0
            help = isInstanceAxis
                ? "\(axis.values.count) stops in the instance grid formula"
                : "Not in the instance grid (contributes ×0)"
            highlighted = isInstanceAxis
        case .pinned:
            count = isInstanceAxis ? axis.values.count : 0
            help = isInstanceAxis
                ? "\(axis.values.count) stops in the instance grid formula"
                : "Pinned — fixed coordinate for all instances"
            highlighted = isInstanceAxis
        }
        return StudioCountBadge(
            text: "\(count)",
            highlighted: highlighted,
            fixedWidth: AxisBlockLayout.stopCountBadgeWidth,
            help: help
        )
    }

    private var axisRangeText: String? {
        guard let min = axis.min, let max = axis.max else { return nil }
        let minText = StudioFormatting.axisValue(min)
        let maxText = StudioFormatting.axisValue(max)
        if let defaultValue = axis.default {
            return "fvar \(minText) – \(StudioFormatting.axisValue(defaultValue)) – \(maxText)"
        }
        return "fvar \(minText) – \(maxText)"
    }

    private func commitDisplayName() {
        onUpdateDisplayName?(editedDisplayName)
        isEditingDisplayName = false
        displayNameFieldFocused = false
    }

    private func cancelDisplayName() {
        isEditingDisplayName = false
        displayNameFieldFocused = false
        editedDisplayName = currentDisplayName
    }
}

