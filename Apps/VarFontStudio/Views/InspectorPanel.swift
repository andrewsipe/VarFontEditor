import SwiftUI
import VarFontCore

/// Instance-scoped inspector content (composed name, chain, coordinates, name table).
struct InstanceInspectorContent: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @State private var showPlannedWrites = true

    var body: some View {
        Group {
            if let instance = resolvedInspectorInstance {
                VStack(spacing: 0) {
                    instanceHeaderBar(instance)

                    instanceInspector(instance)
                }
            } else {
                emptyInspector
            }
        }
        .id(editor.planRevision)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvedInspectorInstance: PlannedInstance? {
        guard let key = editor.inspectorInspectableInstance?.key,
              let live = editor.instancePlan?.instances.first(where: { $0.key == key }) else {
            return editor.inspectorInspectableInstance
        }
        return live
    }

    private func instanceHeaderBar(_ instance: PlannedInstance) -> some View {
        HStack(spacing: StudioSpacing.controlGap) {
            Spacer(minLength: 0)
            if let bundle = editor.primaryConflictAxis(for: instance) {
                StudioInspectorConflictBadge(count: 1) {
                    editor.presentConflictResolver(bundle: bundle)
                }
                .help("Open conflict resolver for \(bundle.axisLabel)")
            }
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal)
        .padding(.vertical, StudioSpacing.panelVertical)
    }

    private var emptyInspector: some View {
        ContentUnavailableView(
            editor.activeInstanceSelection.isEmpty ? "No Instance Selected" : "Select One Instance",
            systemImage: "sidebar.right",
            description: Text(
                editor.activeInstanceSelection.count > 1
                    ? "The inspector shows details for a single instance. Select one row in the instance list."
                    : "Select a row in the instance list to inspect naming, coordinates, and export status."
            )
        )
    }

    private func instanceInspector(_ instance: PlannedInstance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpacing.sectionGap + 4) {
                StudioComposedNameCallout(
                    name: instance.composedName,
                    isDuplicate: instance.duplicate
                )

                if instance.duplicate {
                    StudioConflictAlert(
                        message: "This composed name is shared by other instances.",
                        actionTitle: "Show duplicates…"
                    ) {
                        layout.showInstances = true
                        editor.showDuplicateInstances(matching: instance)
                    }
                }

                inclusionSection(instance)
                namingChainSection(instance)
                axisCoordinatesSection(instance)

                if let bundle = editor.primaryConflictAxis(for: instance) {
                    StudioConflictAlert(
                        message: "Naming conflict on \(bundle.axisLabel) affects this instance.",
                        actionTitle: "Resolve…"
                    ) {
                        editor.presentConflictResolver(bundle: bundle)
                    }
                }

                nameTableSection(instance)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.top, StudioSpacing.panelContentTop)
            .padding(.bottom, StudioSpacing.panelVertical)
        }
    }

    // MARK: - Sections

    private func inclusionSection(_ instance: PlannedInstance) -> some View {
        StudioInspectorBlock(title: "Export inclusion") {
            let included = editor.isInstanceIncluded(instance.key)
            HStack(spacing: StudioSpacing.controlGap) {
                Image(systemName: included ? "checkmark.circle.fill" : "minus.circle.fill")
                    .foregroundStyle(included ? StudioColors.successForeground : StudioColors.warningForeground)
                VStack(alignment: .leading, spacing: 2) {
                    Text(included ? "Included in export" : "Excluded (not included)")
                        .font(StudioTypography.bodyMedium)
                    if !included {
                        Text("This instance will not be written to output.")
                            .font(StudioTypography.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                StudioIncludeCheckbox(isOn: included) {
                    editor.setInstanceIncluded(instance.key, included: !included)
                }
            }
            .frame(minHeight: StudioFieldMetrics.listRowMinHeight)
        }
    }

    private func namingChainSection(_ instance: PlannedInstance) -> some View {
        StudioInspectorBlock(title: "Naming chain") {
            InspectorInstanceNamingChain(links: instance.namingChain) { tag in
                editor.focusInspectorAxis(for: instance, tag: tag)
            }
        }
    }

    private func axisCoordinatesSection(_ instance: PlannedInstance) -> some View {
        let rows = editor.inspectorAxisCoordRows(for: instance)
        let showsElidableColumn = rows.contains(where: \.showsElisionToggle)

        return StudioInspectorBlock(title: "Axis coordinates") {
            VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
                if showsElidableColumn {
                    HStack(spacing: StudioSpacing.controlGap) {
                        Spacer(minLength: 0)
                        Text("Elidable")
                            .font(StudioTypography.columnLabel)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: InspectorAxisCoordLayout.elisionWidth, alignment: .center)
                    }
                }

                InspectorAxisCoordinatesView(
                    rows: rows,
                    selectedStopID: editor.selectedAxisStopID,
                    onRowTap: { row in
                        guard let stopID = row.stopID else { return }
                        editor.focusInspectorAxisStop(tag: row.tag, stopID: stopID)
                    },
                    onElisionToggle: { row in
                        guard let stopID = row.stopID else { return }
                        editor.toggleAxisStopElidable(axisTag: row.tag, stopID: stopID)
                    }
                )
            }
        }
    }

    private func nameTableSection(_ instance: PlannedInstance) -> some View {
        StudioInspectorBlock(title: "Name table IDs") {
            VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        showPlannedWrites.toggle()
                    }
                } label: {
                    HStack(spacing: StudioSpacing.tightGap) {
                        StudioNestedDisclosureChevron(isExpanded: showPlannedWrites)
                        Text("Planned table writes")
                            .font(StudioTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                if showPlannedWrites {
                    let rows = editor.openTypePreviewRows(for: instance)
                    if rows.isEmpty {
                        Text("No planned writes for this instance.")
                            .font(StudioTypography.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, StudioSpacing.tightGap)
                    } else {
                        InspectorOpenTypeTable(rows: rows)
                            .padding(.top, StudioSpacing.panelVertical)
                    }
                }
            }
        }
    }
}
