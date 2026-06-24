import SwiftUI
import VarFontCore

private enum StopEditField: Equatable {
    case value
    case name
}

struct AxisTreePanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var expandedAxes: Set<String> = []
    @State private var editingStop: (id: String, field: StopEditField)?

    var body: some View {
        List {
            if editor.selectedFont != nil {
                gridSummarySection
                if !editor.axisPlanWarnings.isEmpty {
                    warningsSection
                }
                axesSection
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Axis Tree")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let font = editor.selectedFont {
                    Text("\(font.axes.count) axes")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: editor.selectedFontID) {
            editingStop = nil
            resetExpansion()
        }
        .onAppear {
            if expandedAxes.isEmpty {
                resetExpansion()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var gridSummarySection: some View {
        if let plan = editor.instancePlan, !plan.formula.parts.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    studioSummaryRow("Instance grid", value: gridFormulaText(plan))
                    studioSummaryRow("Generated", value: "\(plan.formula.totalGenerated)", monospaced: true)
                }
            }
        }
    }

    private func studioSummaryRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? StudioTypography.monoMeta : StudioTypography.caption)
                .foregroundStyle(.primary)
        }
    }

    private var warningsSection: some View {
        Section {
            ForEach(Array(editor.axisPlanWarnings.enumerated()), id: \.offset) { _, warning in
                Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Warnings")
        }
    }

    private var axesSection: some View {
        Section {
            if let font = editor.selectedFont {
                ForEach(Array(font.axes.enumerated()), id: \.element.id) { index, axis in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 8)
                    }

                    axisBlock(axis)
                }
            }
        }
    }

    @ViewBuilder
    private func axisBlock(_ axis: AxisDefinition) -> some View {
        let isInstanceAxis = axis.role == .instance
        let isExpanded = expandedAxes.contains(axis.tag)

        VStack(alignment: .leading, spacing: 0) {
            AxisTreeAxisHeader(
                axis: axis,
                isExpanded: isExpanded,
                isInstanceAxis: instanceAxisBinding(for: axis.tag),
                onToggleExpansion: { toggleExpansion(for: axis.tag) }
            )

            if isExpanded {
                axisDetail(axis)
                    .padding(.top, 6)
                    .opacity(isInstanceAxis ? 1 : 0.4)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
    }

    // MARK: - Axis detail

    @ViewBuilder
    private func axisDetail(_ axis: AxisDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if axis.values.isEmpty {
                Text("No STAT stops on this axis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                AxisStopTableHeader(showElidable: axis.values.count > 1)

                ForEach(axis.values) { stop in
                    AxisTreeStopRow(
                        axisTag: axis.tag,
                        stop: stop,
                        isSelected: editor.selectedAxisStopID == stop.id,
                        editingField: editingStop?.id == stop.id ? editingStop?.field : nil,
                        showElidable: axis.values.count > 1,
                        isElidable: stop.elidable,
                        onSelect: {
                            editingStop = nil
                            editor.toggleAxisStopSelection(stopID: stop.id)
                        },
                        onBeginEdit: { field in
                            editor.selectedAxisStopID = stop.id
                            editingStop = (stop.id, field)
                        },
                        onEndEdit: { editingStop = nil },
                        onRemove: { editor.removeAxisStop(axisTag: axis.tag, stopID: stop.id) },
                        onCommitValue: { editor.updateAxisStopValue(axisTag: axis.tag, stopID: stop.id, value: $0) },
                        onCommitName: { editor.updateAxisStopName(axisTag: axis.tag, stopID: stop.id, name: $0) },
                        onToggleElidable: { editor.toggleAxisStopElidable(axisTag: axis.tag, stopID: stop.id) }
                    )
                }
            }

            if axis.role == .instance {
                Button {
                    editor.addAxisStop(axisTag: axis.tag)
                    if let newID = editor.selectedAxisStopID {
                        editingStop = (newID, .name)
                    }
                } label: {
                    Label("Add Stop", systemImage: "plus")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, AxisBlockLayout.valueColumnLeading)
                        .padding(.vertical, 5)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.tertiary)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings

    private func toggleExpansion(for tag: String) {
        if expandedAxes.contains(tag) {
            expandedAxes.remove(tag)
        } else {
            expandedAxes.insert(tag)
        }
    }

    private func instanceAxisBinding(for tag: String) -> Binding<Bool> {
        Binding(
            get: {
                editor.selectedFont?.axes.first(where: { $0.tag == tag })?.role == .instance
            },
            set: { editor.setAxisInstanceGridEnabled(tag: tag, enabled: $0) }
        )
    }

    private func resetExpansion() {
        guard let font = editor.selectedFont else {
            expandedAxes = []
            return
        }
        expandedAxes = Set(
            font.axes.filter { $0.role == .instance || !$0.values.isEmpty }.map(\.tag)
        )
    }

    private func gridFormulaText(_ plan: InstancePlan) -> String {
        let parts = plan.formula.parts.map(String.init).joined(separator: " × ")
        return "\(parts) = \(plan.formula.totalGenerated)"
    }
}

// MARK: - Axis header

private struct AxisTreeAxisHeader: View {
    let axis: AxisDefinition
    let isExpanded: Bool
    @Binding var isInstanceAxis: Bool
    let onToggleExpansion: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleExpansion) {
                HStack(spacing: AxisBlockLayout.tagNameSpacing) {
                    StudioTagPill(text: axis.tag)
                        .frame(width: AxisBlockLayout.tagColumnWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(axis.displayName ?? axis.tag)
                                .font(StudioTypography.body)
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        if let range = axisRangeText {
                            Text(range)
                                .font(StudioTypography.meta)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .help("fvar minimum · default · maximum")
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Toggle("Instance axis", isOn: $isInstanceAxis)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(
                    "When on, stops on this axis generate named instances. "
                        + "When off, the axis stays at its default value for every instance."
                )
                .accessibilityLabel("Instance axis")

            stopCountBadge
        }
    }

    private var stopCountBadge: some View {
        Text("\(isInstanceAxis ? axis.values.count : 0)")
            .font(StudioTypography.meta.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(isInstanceAxis ? .secondary : .tertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(isInstanceAxis ? 1 : 0.6), in: Capsule())
            .help(
                isInstanceAxis
                    ? "\(axis.values.count) stops in the instance grid formula"
                    : "Not in the instance grid (contributes ×0)"
            )
    }

    private var axisRangeText: String? {
        guard let min = axis.min, let max = axis.max else { return nil }
        let minText = StudioFormatting.axisValue(min)
        let maxText = StudioFormatting.axisValue(max)
        if let defaultValue = axis.default {
            return "\(minText) – \(StudioFormatting.axisValue(defaultValue)) – \(maxText)"
        }
        return "\(minText) – \(maxText)"
    }
}

// MARK: - Axis block layout

/// Shared horizontal metrics so the header badge/name line up with stop rows.
private enum AxisBlockLayout {
    /// Fixed slot for the axis tag pill — matches typical four-letter tags (`wdth`, `wght`, …).
    static let tagColumnWidth: CGFloat = 34
    static let tagNameSpacing: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 6

    /// Left edge of the semantic name and Value column (from the axis block edge).
    static var valueColumnLeading: CGFloat {
        tagColumnWidth + tagNameSpacing
    }

    /// Width for right-aligned axis values (up to ~5 monospaced digits).
    static let valueColumnWidth: CGFloat = 40
    static let nameGap: CGFloat = 12
    static let elidableWidth: CGFloat = 52

    /// Gutter between the badge (highlight left edge) and the Value column.
    static var removeGutterWidth: CGFloat {
        valueColumnLeading - rowHorizontalPadding
    }

    static let removeButtonSize: CGFloat = StudioIncludeCheckbox.size

    /// Horizontal center of the leading-aligned tag pill (intrinsic width, not the full tag column slot).
    static func tagBadgeCenterX(for tag: String) -> CGFloat {
        StudioTagPill.layoutWidth(for: tag) / 2
    }

    /// Leading offset for a fixed-size remove control inside the row gutter.
    static func removeButtonLeadingOffset(for tag: String) -> CGFloat {
        tagBadgeCenterX(for: tag) - rowHorizontalPadding - removeButtonSize / 2
    }
}

private struct AxisStopTableHeader: View {
    let showElidable: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: AxisBlockLayout.removeGutterWidth)

            Text("Value")
                .font(StudioTypography.columnLabel)
                .foregroundStyle(.tertiary)
                .frame(width: AxisBlockLayout.valueColumnWidth, alignment: .trailing)

            Text("Name")
                .font(StudioTypography.columnLabel)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AxisBlockLayout.nameGap)

            if showElidable {
                Text("Elidable")
                    .font(StudioTypography.columnLabel)
                    .foregroundStyle(.tertiary)
                    .frame(width: AxisBlockLayout.elidableWidth, alignment: .center)
                    .help("Omit this stop from the composed style name when it is the default choice")
            }
        }
        .padding(.horizontal, AxisBlockLayout.rowHorizontalPadding)
        .padding(.bottom, 2)
    }
}

// MARK: - Stop row

private struct AxisTreeStopRow: View {
    let axisTag: String
    let stop: AxisValue
    let isSelected: Bool
    let editingField: StopEditField?
    let showElidable: Bool
    let isElidable: Bool
    let onSelect: () -> Void
    let onBeginEdit: (StopEditField) -> Void
    let onEndEdit: () -> Void
    let onRemove: () -> Void
    let onCommitValue: (Double) -> Void
    let onCommitName: (String) -> Void
    let onToggleElidable: () -> Void

    @State private var isHovered = false
    @State private var editingValue = ""
    @State private var editingName = ""
    @State private var confirmRemove = false
    @State private var selectTask: Task<Void, Never>?
    @FocusState private var focusedField: StopEditField?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            removeGutter

            valueColumn
                .frame(width: AxisBlockLayout.valueColumnWidth, alignment: .trailing)

            nameColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AxisBlockLayout.nameGap)

            if stop.statFormat == 3 {
                StudioTagPill(text: "Linked", compact: true)
                    .padding(.leading, 6)
            }

            if showElidable {
                ElidableColumn(isOn: isElidable, action: onToggleElidable)
                    .frame(width: AxisBlockLayout.elidableWidth)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, AxisBlockLayout.rowHorizontalPadding)
        .background {
            StudioRowBackground(isSelected: isSelected, isHovered: isHovered)
                .padding(.leading, -AxisBlockLayout.rowHorizontalPadding)
        }
        .onHover { isHovered = $0 }
        .onAppear { syncDrafts() }
        .onChange(of: stop.value) { _, _ in syncDrafts() }
        .onChange(of: stop.name) { _, _ in syncDrafts() }
        .onChange(of: editingField) { _, field in
            syncDrafts()
            focusedField = field
        }
        .onChange(of: focusedField) { _, field in
            if field == nil, editingField != nil {
                commitCurrentEdit()
                onEndEdit()
            }
        }
        .alert("Remove Stop?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove “\(stop.name)” at \(StudioFormatting.axisValue(stop.value))?")
        }
    }

    @ViewBuilder
    private var removeGutter: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(
                    width: AxisBlockLayout.removeGutterWidth,
                    height: AxisBlockLayout.removeButtonSize
                )

            if isHovered {
                Button {
                    confirmRemove = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AxisBlockLayout.removeButtonSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(
                    width: AxisBlockLayout.removeButtonSize,
                    height: AxisBlockLayout.removeButtonSize
                )
                .offset(x: AxisBlockLayout.removeButtonLeadingOffset(for: axisTag))
                .help("Remove stop")
            }
        }
        .frame(width: AxisBlockLayout.removeGutterWidth)
    }

    @ViewBuilder
    private var valueColumn: some View {
        if editingField == .value {
            TextField("Value", text: $editingValue)
                .textFieldStyle(.plain)
                .font(StudioTypography.monoValue)
                .foregroundStyle(StudioColors.axisValue)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .value)
                .onSubmit(commitValue)
        } else {
            Text(StudioFormatting.axisValue(stop.value))
                .font(StudioTypography.monoValue)
                .foregroundStyle(StudioColors.axisValue)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .gesture(clickGesture(for: .value))
        }
    }

    @ViewBuilder
    private var nameColumn: some View {
        if editingField == .name {
            TextField("Name", text: $editingName)
                .textFieldStyle(.plain)
                .font(StudioTypography.body)
                .focused($focusedField, equals: .name)
                .onSubmit(commitName)
        } else {
            Text(stop.name)
                .font(StudioTypography.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(clickGesture(for: .name))
        }
    }

    private func clickGesture(for field: StopEditField) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                selectTask?.cancel()
                onBeginEdit(field)
            }
            .simultaneously(with:
                TapGesture(count: 1)
                    .onEnded {
                        selectTask?.cancel()
                        selectTask = Task {
                            try? await Task.sleep(nanoseconds: 220_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run { onSelect() }
                        }
                    }
            )
    }

    private func syncDrafts() {
        editingValue = StudioFormatting.axisValue(stop.value)
        editingName = stop.name
    }

    private func commitCurrentEdit() {
        switch editingField {
        case .value:
            commitValue()
        case .name:
            commitName()
        case nil:
            break
        }
    }

    private func commitValue() {
        let trimmed = editingValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed) else {
            syncDrafts()
            return
        }
        onCommitValue(value)
    }

    private func commitName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            syncDrafts()
            return
        }
        onCommitName(trimmed)
    }
}

private struct ElidableColumn: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            ElidableDot(isOn: isOn)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded { action() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elidable")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityAction { action() }
        .help(isOn ? "Clear elidable stop" : "Mark as elidable stop")
    }
}

private struct ElidableDot: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: 14, height: 14)
            if isOn {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .allowsHitTesting(false)
    }
}
