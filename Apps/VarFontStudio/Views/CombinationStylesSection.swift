import SwiftUI
import VarFontCore

struct CombinationStylesSection: View {
    @EnvironmentObject private var editor: EditorViewModel

    let compounds: [CompoundStatValue]
    let axes: [AxisDefinition]

    @State private var isExpanded = true
    @State private var editingLeg: (compoundID: String, tag: String)?
    @State private var legDraft = ""

    private var axisTags: Set<String> {
        Set(axes.map(\.tag))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            disclosureHeader

            if isExpanded {
                VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
                    ForEach(compounds) { compound in
                        compoundRow(compound)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclosureHeader: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: StudioSpacing.controlGap) {
                StudioNestedDisclosureChevron(isExpanded: isExpanded)
                Text("Combination styles")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
                Text("\(compounds.count) preset\(compounds.count == 1 ? "" : "s") · format 4")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
            }
            .frame(height: StudioFieldMetrics.disclosureLabelRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Named multi-axis points in STAT. They do not multiply the instance grid.")
    }

    private func compoundRow(_ compound: CompoundStatValue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 0) {
                Color.clear
                    .frame(width: StopTableLayout.stopIndentWidth)

                compoundNameField(compound)
                    .frame(maxWidth: .infinity, alignment: .leading)

                StudioElidableSwitch(isOn: compound.elidable) {
                    editor.updateCompoundStatElidable(id: compound.id, elidable: !compound.elidable)
                }
                .frame(width: StopTableLayout.elidableWidth)
            }
            .frame(minHeight: StudioFieldMetrics.listRowMinHeight)

            compoundSubline(compound)
                .padding(.leading, StopTableLayout.stopIndentWidth + StudioSpace.x1)
        }
        .padding(.horizontal, StopTableLayout.rowHorizontalPadding)
        .padding(.vertical, StudioSpacing.instanceRowVertical)
    }

    private func compoundNameField(_ compound: CompoundStatValue) -> some View {
        StudioTextField(
            placeholder: "Regular",
            text: Binding(
                get: { compound.name },
                set: { editor.updateCompoundStatName(id: compound.id, name: $0) }
            ),
            font: StudioTypography.bodyMedium,
            rowHeight: StudioFieldMetrics.bodyMediumRowHeight,
            filledForeground: StudioColors.registrationForeground
        )
    }

    @ViewBuilder
    private func compoundSubline(_ compound: CompoundStatValue) -> some View {
        let tags = compound.coords.keys.sorted()
        HStack(spacing: StudioSpacing.rowGap) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                if index > 0 {
                    Text("+")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                }
                legView(compound: compound, tag: tag)
            }
        }
    }

    @ViewBuilder
    private func legView(compound: CompoundStatValue, tag: String) -> some View {
        let value = compound.coords[tag] ?? 0
        let missingAxis = !axisTags.contains(tag)
        let isEditing = editingLeg?.compoundID == compound.id && editingLeg?.tag == tag

        if isEditing {
            StudioInlineTextField(
                placeholder: tag,
                text: $legDraft,
                font: StudioTypography.monoMeta,
                foreground: missingAxis ? StudioColors.warningForeground : StudioColors.axisValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                alignment: .leading,
                onSubmit: { commitLegEdit(compoundID: compound.id, tag: tag) },
                onCancel: { editingLeg = nil }
            )
            .onAppear { legDraft = StudioFormatting.axisValue(value) }
        } else {
            Button {
                editingLeg = (compound.id, tag)
                legDraft = StudioFormatting.axisValue(value)
            } label: {
                HStack(spacing: 2) {
                    Text(tag)
                        .font(StudioTypography.monoMeta)
                        .foregroundStyle(
                            missingAxis
                                ? AnyShapeStyle(StudioColors.warningForeground)
                                : AnyShapeStyle(.tertiary)
                        )
                    Text("=")
                        .font(StudioTypography.monoMeta)
                        .foregroundStyle(.tertiary)
                    Text(StudioFormatting.axisValue(value))
                        .font(StudioTypography.monoMeta)
                        .foregroundStyle(missingAxis ? StudioColors.warningForeground : StudioColors.axisValue)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func commitLegEdit(compoundID: String, tag: String) {
        guard let value = Double(legDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            editingLeg = nil
            return
        }
        editor.updateCompoundStatCoordinate(id: compoundID, tag: tag, value: value)
        editingLeg = nil
    }
}
