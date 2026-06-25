import AppKit
import SwiftUI
import VarFontCore

struct InstanceListPanel: View {
    @EnvironmentObject private var editor: EditorViewModel

    /// Matches list row checkbox column: list inset + row horizontal padding.
    private static let checkboxLeading = StudioSpacing.listInset + StudioSpacing.rowHorizontal

    private var display: InstanceListDisplay {
        editor.instanceListDisplay
    }

    var body: some View {
        VStack(spacing: 0) {
            StudioPanelHeader(title: "Instances") {
                if !display.isEmpty {
                    instanceHeaderCounts
                }
            }

            filterBar

            if editor.selectedFont == nil {
                ContentUnavailableView(
                    "No Font Open",
                    systemImage: "textformat.size",
                    description: Text("Open or drop a variable font to generate instances.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if display.isEmpty {
                ContentUnavailableView(
                    emptyListTitle,
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(emptyListMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                instanceList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var visibleInstanceCount: Int {
        display.groups.reduce(0) { $0 + $1.instances.count }
    }

    private var instanceHeaderCounts: some View {
        HStack(spacing: 3) {
            Text("\(visibleInstanceCount)")
                .foregroundStyle(StudioColors.computedHighlight)
            Text("shown")
                .foregroundStyle(.secondary)

            if let plan = editor.instancePlan {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("\(plan.formula.totalIncluded)")
                    .foregroundStyle(StudioColors.computedHighlight)
                Text("included")
                    .foregroundStyle(.secondary)
            }
        }
        .font(StudioTypography.meta)
        .lineLimit(1)
    }

    private var instanceList: some View {
        ScrollView {
            LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                ForEach(display.groups) { group in
                    if group.label.isEmpty {
                        ForEach(group.instances) { instance in
                            instanceRow(instance)
                        }
                    } else {
                        Section {
                            ForEach(group.instances) { instance in
                                instanceRow(instance)
                            }
                        } header: {
                            StudioGroupHeader(label: group.label, count: group.instances.count)
                        }
                    }
                }
            }
            .padding(.horizontal, StudioSpacing.listInset)
            .padding(.vertical, StudioSpacing.panelVertical)
        }
        .transaction { $0.animation = nil }
    }

    private func instanceRow(_ instance: PlannedInstance) -> some View {
        InstanceRowView(
            instance: instance,
            coordsCaption: display.coordCaptions[instance.key] ?? "",
            isIncluded: display.includedByKey[instance.key] ?? true,
            isSelected: editor.activeInstanceSelection.contains(instance.key),
            onSelect: { extend in
                editor.selectInstance(key: instance.key, extend: extend)
            },
            onIncludedChange: { editor.setInstanceIncluded(instance.key, included: $0) },
            onSetSelectionIncluded: { included in
                let keys = editor.activeInstanceSelection.contains(instance.key)
                    ? editor.activeInstanceSelection
                    : [instance.key]
                editor.setInstancesIncluded(keys: keys, included: included)
            }
        )
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: navigation
            HStack(alignment: .center, spacing: StudioSpacing.controlGap) {
                if let label = display.axisStopFilterLabel {
                    StudioFilterChip(icon: nil, label: label) {
                        Button {
                            editor.clearAxisStopFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(StudioTypography.meta)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear axis stop filter")
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: 0)

                searchField
                    .frame(width: 180)
            }
            .padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.top, StudioSpacing.toolbarVertical)
            .padding(.bottom, StudioSpacing.rowGap - 1)
            .animation(.easeOut(duration: 0.15), value: display.axisStopFilterLabel)

            // Row 2: bulk include (checkbox column aligned with list rows)
            HStack(alignment: .center, spacing: StudioSpacing.rowGap + 1) {
                StudioIncludeCheckbox(
                    isOn: editor.allVisibleInstancesIncluded,
                    isIndeterminate: editor.hasMixedVisibleInclusion
                ) {
                    editor.toggleAllVisibleInstancesIncluded()
                }
                .disabled(editor.filteredInstances.isEmpty)

                Text("Include all")
                    .font(StudioTypography.meta)
                    .foregroundStyle(editor.filteredInstances.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: StudioSpacing.controlGap)

                showFilterPicker
                    .frame(width: 180, alignment: .trailing)
            }
            .padding(.leading, Self.checkboxLeading)
            .padding(.trailing, StudioSpacing.panelHorizontal)
            .padding(.bottom, StudioSpacing.toolbarVertical)
            .opacity(editor.filteredInstances.isEmpty && display.axisStopFilterLabel == nil ? 0.45 : 1)

            Divider()
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)

            TextField("Search names or coordinates", text: $editor.searchText)
                .textFieldStyle(.plain)
                .font(StudioTypography.caption)

            if !editor.searchText.isEmpty {
                Button {
                    editor.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            .quaternary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: StudioRadius.chip)
        )
    }

    private var showFilterPicker: some View {
        HStack(spacing: 4) {
            Text("Show")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
                .fixedSize()

            Picker("Show", selection: $editor.instanceFilter) {
                ForEach(InstanceFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var emptyListTitle: String {
        if editor.instanceFilter == .excluded && editor.searchText.isEmpty && display.axisStopFilterLabel == nil {
            return "No Excluded Instances"
        }
        return "No Matching Instances"
    }

    private var emptyListMessage: String {
        if display.axisStopFilterLabel != nil {
            return "No instances match the selected axis stop. Click the stop again to clear the filter."
        }
        if editor.instanceFilter == .excluded && editor.searchText.isEmpty {
            return "No excluded instances — all are included in this export."
        }
        if !editor.searchText.isEmpty || editor.instanceFilter != .all {
            return "Try clearing the search or switching the inclusion filter."
        }
        return "This font has no generated instances."
    }
}

private struct InstanceRowView: View {
    let instance: PlannedInstance
    let coordsCaption: String
    let isIncluded: Bool
    let isSelected: Bool
    let onSelect: (Bool) -> Void
    let onIncludedChange: (Bool) -> Void
    let onSetSelectionIncluded: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: StudioSpacing.rowGap + 1) {
            StudioIncludeCheckbox(isOn: isIncluded) {
                onIncludedChange(!isIncluded)
            }

            Text(instance.composedName)
                .font(StudioTypography.bodyMedium)
                .foregroundStyle(isIncluded ? .primary : .secondary)
                .strikethrough(!isIncluded, color: .secondary)
                .lineLimit(1)

            if instance.duplicate {
                StudioWarningBadge(help: "Duplicate composed name")
            }

            Spacer(minLength: StudioSpacing.controlGap)

            Text(coordsCaption)
                .font(StudioTypography.monoMeta)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .trailing)
        }
        .studioRowInsets()
        .opacity(isIncluded ? 1 : 0.45)
        .background(
            StudioRowBackground(
                isSelected: isSelected,
                isHovered: isHovered,
                isWarning: instance.duplicate
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioRadius.row))
        .onTapGesture {
            onSelect(NSEvent.modifierFlags.contains(.command))
        }
        .contextMenu {
            InstanceSelectionContextMenu(
                includeAction: { onSetSelectionIncluded(true) },
                excludeAction: { onSetSelectionIncluded(false) }
            )
        }
        .onHover { isHovered = $0 }
    }
}
