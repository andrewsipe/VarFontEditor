import AppKit
import SwiftUI
import VarFontCore

struct InstanceListPanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @AppStorage("instanceListHideElided") private var hideElidedNames = false
    @FocusState private var isSearchFocused: Bool

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
        .onAppear {
            focusSearchFieldIfRequested()
        }
        .onChange(of: editor.instanceSearchFocusToken) { _, token in
            guard token != nil else { return }
            focusSearchFieldIfRequested()
        }
    }

    private func focusSearchFieldIfRequested() {
        guard editor.instanceSearchFocusToken != nil else { return }
        DispatchQueue.main.async {
            isSearchFocused = true
        }
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
            LazyVStack(spacing: StudioSpacing.instanceRowGap, pinnedViews: [.sectionHeaders]) {
                ForEach(Array(display.groups.enumerated()), id: \.element.id) { index, group in
                    if group.label.isEmpty {
                        VStack(spacing: StudioSpacing.instanceRowGap) {
                            ForEach(group.instances) { instance in
                                instanceRow(instance)
                                    .id("\(instance.key)-\(instance.duplicate)-\(editor.planRevision)")
                            }
                        }
                    } else {
                        Section {
                            VStack(spacing: StudioSpacing.instanceRowGap) {
                                ForEach(group.instances) { instance in
                                    instanceRow(instance)
                                        .id("\(instance.key)-\(instance.duplicate)-\(editor.planRevision)")
                                }
                            }
                            .padding(.top, StudioSpacing.groupHeaderBelow)
                            .padding(.bottom, sectionTrailingGap(after: index))
                        } header: {
                            StudioGroupHeader(
                                label: group.label,
                                count: group.instances.count
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, StudioSpacing.listInset)
            .padding(.bottom, StudioSpacing.panelVertical)
        }
        .transaction { $0.animation = nil }
    }

    /// Space after the last row, before the next section header (lives in scroll content, not the pin target).
    private func sectionTrailingGap(after index: Int) -> CGFloat {
        index < display.groups.count - 1 ? StudioSpacing.sectionGap : 0
    }

    private func instanceRow(_ instance: PlannedInstance) -> some View {
        let hasConflict = editor.instanceAffectedByUnresolvedConflict(instance)
        return InstanceRowView(
            instance: instance,
            coordsCaption: display.coordCaptions[instance.key] ?? "",
            isIncluded: display.includedByKey[instance.key] ?? true,
            isSelected: editor.activeInstanceSelection.contains(instance.key),
            hideElidedNames: hideElidedNames,
            isDuplicate: instance.duplicate,
            hasConflict: hasConflict,
            onSelect: { extend in
                editor.selectInstance(key: instance.key, extend: extend)
            },
            onIncludedChange: { editor.setInstanceIncluded(instance.key, included: $0) },
            onSetSelectionIncluded: { included in
                let keys = editor.activeInstanceSelection.contains(instance.key)
                    ? editor.activeInstanceSelection
                    : [instance.key]
                editor.setInstancesIncluded(keys: keys, included: included)
            },
            onWarningTap: hasConflict ? {
                if let bundle = editor.primaryConflictAxis(for: instance) {
                    editor.presentConflictResolver(bundle: bundle)
                }
            } : nil,
            onDuplicateTap: instance.duplicate ? {
                layout.showInstances = true
                editor.showDuplicateInstances(matching: instance)
            } : nil
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

                Toggle(isOn: $hideElidedNames) {
                    Text("Hide elided")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(editor.filteredInstances.isEmpty)

                Spacer(minLength: StudioSpacing.controlGap)

                showFilterPicker
            }
            .padding(.leading, Self.checkboxLeading)
            .padding(.trailing, StudioSpacing.panelHorizontal)
            .padding(.bottom, StudioSpacing.toolbarVertical)
            .opacity(editor.filteredInstances.isEmpty && display.axisStopFilterLabel == nil ? 0.45 : 1)

            Divider()
        }
    }

    private var searchField: some View {
        StudioSearchField(
            text: $editor.searchText,
            placeholder: "Search names or coordinates",
            isFocused: $isSearchFocused
        )
    }

    private var showFilterPicker: some View {
        HStack(spacing: 4) {
            Text("Show")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
                .fixedSize()

            HStack(spacing: 1) {
                ForEach(editor.visibleInstanceFilters) { filter in
                    showFilterButton(filter)
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StudioRadius.control))
        }
    }

    private func showFilterButton(_ filter: InstanceFilter) -> some View {
        let isSelected = editor.instanceFilter == filter
        let isDuplicates = filter == .duplicates

        return Button {
            editor.instanceFilter = filter
        } label: {
            Text(filter.label)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(showFilterForeground(isSelected: isSelected, isDuplicates: isDuplicates))
                .background(
                    showFilterBackground(isSelected: isSelected, isDuplicates: isDuplicates),
                    in: RoundedRectangle(cornerRadius: StudioRadius.small)
                )
        }
        .buttonStyle(.plain)
        .studioCompactControl()
        .help(isDuplicates ? "Show instances that share a composed style name" : filter.label)
    }

    private func showFilterForeground(isSelected: Bool, isDuplicates: Bool) -> Color {
        if isDuplicates {
            return StudioColors.warningForeground
        }
        return isSelected ? Color.primary : Color.secondary
    }

    private func showFilterBackground(isSelected: Bool, isDuplicates: Bool) -> Color {
        if isDuplicates {
            return isSelected
                ? StudioColors.warningFill
                : StudioColors.warningFill.opacity(0.45)
        }
        return isSelected ? Color.primary.opacity(0.12) : Color.clear
    }

    private var emptyListTitle: String {
        if editor.instanceFilter == .duplicates && editor.searchText.isEmpty && display.axisStopFilterLabel == nil {
            return "No Duplicate Instances"
        }
        if editor.instanceFilter == .excluded && editor.searchText.isEmpty && display.axisStopFilterLabel == nil {
            return "No Excluded Instances"
        }
        return "No Matching Instances"
    }

    private var emptyListMessage: String {
        if display.axisStopFilterLabel != nil {
            return "No instances match the selected axis stop. Click the stop again to clear the filter."
        }
        if editor.instanceFilter == .duplicates && editor.searchText.isEmpty {
            return "No instances share a composed style name in this plan."
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
    var hideElidedNames: Bool = false
    var isDuplicate: Bool = false
    var hasConflict: Bool = false
    let onSelect: (Bool) -> Void
    let onIncludedChange: (Bool) -> Void
    let onSetSelectionIncluded: (Bool) -> Void
    var onWarningTap: (() -> Void)?
    var onDuplicateTap: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        rowContent
            .opacity(isIncluded ? 1 : 0.45)
            .background {
                StudioRowBackground(
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isWarning: isDuplicate
                )
            }
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

    private var rowContent: some View {
        HStack(spacing: StudioSpacing.rowGap + 1) {
            StudioIncludeCheckbox(isOn: isIncluded) {
                onIncludedChange(!isIncluded)
            }

            StudioInstanceComposedName(
                links: instance.namingChain,
                fallback: instance.composedName,
                included: isIncluded,
                hideElided: hideElidedNames
            )
            .strikethrough(!isIncluded, color: .secondary)

            Color.clear
                .frame(width: StudioWarningBadge.slotSize, height: StudioWarningBadge.slotSize)
                .overlay {
                    if hasConflict {
                        StudioWarningBadge(help: "Naming conflict — show in inspector") {
                            onWarningTap?()
                        }
                    } else if isDuplicate {
                        StudioWarningBadge(help: "Duplicate composed name — show matching instances") {
                            onDuplicateTap?()
                        }
                    }
                }

            Spacer(minLength: StudioSpacing.controlGap)

            Text(coordsCaption)
                .font(StudioTypography.monoMeta)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .trailing)
        }
        .frame(minHeight: StudioFieldMetrics.listRowMinHeight)
        .studioRowInsets()
    }
}
