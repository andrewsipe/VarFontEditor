import SwiftUI
import VarFontCore

struct InstanceListPanel: View {
    @EnvironmentObject private var editor: EditorViewModel

    private var display: InstanceListDisplay {
        editor.instanceListDisplay
    }

    var body: some View {
        VStack(spacing: 0) {
            FontFileTabs()
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
                    "No Matching Instances",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(emptyListMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                instanceList
            }
        }
        .navigationTitle("Instances")
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
            isSelected: editor.selectedInstanceKey == instance.key,
            onSelect: { editor.selectedInstanceKey = instance.key },
            onIncludedChange: { editor.setInstanceIncluded(instance.key, included: $0) }
        )
    }

    private var filterBar: some View {
        StudioCompactToolbar {
            VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
                HStack(spacing: StudioSpacing.controlGap) {
                    TextField("Search names or coordinates", text: $editor.searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(StudioTypography.caption)
                        .controlSize(.small)

                    Picker("Show", selection: $editor.instanceFilter) {
                        ForEach(InstanceFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize()

                    Button("All") {
                        editor.setFilteredInstancesIncluded(true)
                    }
                    .studioCompactControl()
                    .disabled(editor.filteredInstances.isEmpty)

                    Button("None") {
                        editor.setFilteredInstancesIncluded(false)
                    }
                    .studioCompactControl()
                    .disabled(editor.filteredInstances.isEmpty)
                }

                HStack(spacing: StudioSpacing.controlGap) {
                    if let label = display.axisStopFilterLabel {
                        StudioFilterChip(icon: "line.3.horizontal.decrease", label: label) {
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
                    }

                    if let summary = display.summary {
                        Text(summary)
                            .font(StudioTypography.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if editor.selectedFont?.dirty == true {
                        Text("Edited")
                            .font(StudioTypography.meta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var emptyListMessage: String {
        if display.axisStopFilterLabel != nil {
            return "No instances match the selected axis stop. Click the stop again to clear the filter."
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
    let onSelect: () -> Void
    let onIncludedChange: (Bool) -> Void

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
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.orange)
                    .help("Duplicate composed name")
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
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}
