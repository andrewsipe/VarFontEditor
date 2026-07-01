import AppKit
import SwiftUI
import VarFontCore

private enum StopEditField: Equatable {
    case value
    case name
}

private struct AddAxisStopRequest: Identifiable {
    let axisTag: String
    var id: String { axisTag }
}

struct AxisTreePanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @State private var expandedAxes: Set<String> = []
    @State private var editingStop: (id: String, field: StopEditField)?
    @State private var addStopRequest: AddAxisStopRequest?
    @State private var tabKeyMonitor: TabKeyMonitor?
    @State private var activeTabNavigation: ((Bool) -> Void)?
    @State private var activeTabStopID: String?

    var body: some View {
        VStack(spacing: 0) {
            StudioPanelHeader(title: "Axis tree") {
                HStack(spacing: StudioSpacing.controlGap) {
                    if let font = editor.selectedFont {
                        HStack(spacing: 3) {
                            Text("\(font.axes.count)")
                                .foregroundStyle(StudioColors.computedHighlight)
                            Text("axes")
                                .foregroundStyle(.secondary)
                        }
                        .font(StudioTypography.meta)
                    }

                    if editor.isSelectedFontMaster, editor.projectHasMultipleFiles {
                        Button("Push to tree") {
                            editor.pushMasterAxisTreeToAllFonts()
                        }
                        .font(StudioTypography.meta)
                        .buttonStyle(.plain)
                        .help("Copy master axis stops to all other files in this project")
                    }

                    StudioToolbarIconButton(
                        systemName: "sidebar.left",
                        help: "Collapse axis tree"
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            layout.axisTreeCollapsed = true
                        }
                    }
                }
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if editor.selectedFont != nil {
                            gridSummaryContent
                            axesContent
                        }
                    }
                    .padding(.leading, StudioSpacing.scrollContentHorizontal)
                    .padding(.trailing, StudioSpacing.scrollContentHorizontal + StudioSpacing.scrollGutter)
                    .padding(.top, StudioSpacing.panelContentTop)
                    .padding(.bottom, StudioSpacing.panelVertical)
                }
                .transaction { $0.animation = nil }
                .onChange(of: editor.axisTreeFocusRequest) { _, request in
                    guard let request else { return }
                    scrollToAxisStop(
                        scrollProxy: scrollProxy,
                        axisTag: request.axisTag,
                        stopID: request.stopID
                    )
                }
                .onChange(of: editor.inspectorFocusedAxisTag) { _, tag in
                    if let tag {
                        expandedAxes.insert(tag)
                    }
                }
                .onChange(of: editor.selectedAxisStopID) { _, stopID in
                    guard let stopID, editor.axisTreeFocusRequest == nil else { return }
                    expandAxisContaining(stopID: stopID)
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollProxy.scrollTo(stopID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onChange(of: editor.selectedFontID) {
            editingStop = nil
            resetExpansion()
        }
        .onChange(of: editingStop?.id) { _, stopID in
            if stopID == nil {
                tabKeyMonitor?.stop()
                tabKeyMonitor = nil
                activeTabNavigation = nil
                activeTabStopID = nil
            }
        }
        .onAppear {
            if expandedAxes.isEmpty {
                resetExpansion()
            }
        }
        .sheet(item: $addStopRequest) { request in
            if let axis = editor.selectedFont?.axes.first(where: { $0.tag == request.axisTag }) {
                AddAxisStopSheet(axis: axis) {
                    addStopRequest = nil
                }
                .environmentObject(editor)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var gridSummaryContent: some View {
        if let plan = editor.instancePlan, !plan.formula.parts.isEmpty {
            VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
                studioSummaryRow("Instance grid", value: gridFormulaText(plan))
                studioSummaryRow("Generated", value: "\(plan.formula.totalGenerated)", monospaced: true)
            }
            .padding(.bottom, StudioSpacing.sectionGap)
        }
    }

    private func studioSummaryRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? StudioTypography.gridSummaryValueMono : StudioTypography.gridSummaryValue)
                .foregroundStyle(StudioColors.computedHighlight)
                .monospacedDigit()
        }
    }

    private var conflictAlertMessage: String {
        let count = editor.unresolvedAxisConflictCount
        if count == 1, let bundle = editor.axisConflictBundles.first {
            return "Naming conflict on \(bundle.axisLabel) (\(bundle.axisTag))"
        }
        return "\(count) axes need attention"
    }

    @ViewBuilder
    private var axesContent: some View {
        if editor.unresolvedAxisConflictCount > 0 {
            StudioConflictAlert(
                message: conflictAlertMessage,
                actionTitle: editor.unresolvedAxisConflictCount == 1 ? "Resolve…" : "Review…"
            ) {
                editor.presentFirstConflictResolver()
            }
            .padding(.bottom, StudioSpacing.controlGap)
        }

        if let font = editor.selectedFont {
            LazyVStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                ForEach(font.axes) { axis in
                    axisBlock(axis)
                        .id(axis.tag)
                }
            }
        }
    }

    @ViewBuilder
    private func axisBlock(_ axis: AxisDefinition) -> some View {
        let isInstanceAxis = axis.role == .instance
        let isExpanded = expandedAxes.contains(axis.tag)
        let detailOpacity: Double = (isInstanceAxis || axis.isDesignRecordOnly) ? 1 : 0.4

        VStack(alignment: .leading, spacing: 0) {
            AxisTreeAxisHeader(
                axis: axis,
                isExpanded: isExpanded,
                hasConflict: editor.bundle(for: axis.tag) != nil,
                isInstanceAxis: instanceAxisBinding(for: axis.tag),
                onToggleExpansion: { toggleExpansion(for: axis.tag) },
                onResolveConflict: {
                    editor.presentConflictResolver(for: axis.tag)
                }
            )

            if isExpanded {
                axisDetail(axis)
                    .padding(.top, 4)
                    .opacity(detailOpacity)
            }
        }
    }

    // MARK: - Axis detail

    @ViewBuilder
    private func axisDetail(_ axis: AxisDefinition) -> some View {
        VStack(alignment: .leading, spacing: StudioSpacing.instanceRowGap) {
            if axis.isDesignRecordOnly {
                DesignRecordAxisLabelRow(
                    tag: axis.tag,
                    displayName: displayNameBinding(for: axis.tag)
                )
            }

            if axis.values.isEmpty {
                Text(axis.isDesignRecordOnly
                    ? "No STAT axis values on this design axis"
                    : "No STAT stops on this axis")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                AxisStopTableHeader(showElidable: axis.role == .instance)

                ForEach(axis.values) { stop in
                    AxisTreeStopRow(
                        axisTag: axis.tag,
                        stop: stop,
                        isSelected: editor.selectedAxisStopID == stop.id,
                        editingField: editingStop?.id == stop.id ? editingStop?.field : nil,
                        showElidable: axis.role == .instance,
                        allowsRemove: !axis.isDesignRecordOnly,
                        valueEditable: axis.hasFvarScale,
                        isElidable: stop.elidable,
                        onSelect: {
                            scheduleClearEdit()
                            editor.toggleAxisStopSelection(stopID: stop.id)
                        },
                        onBeginEdit: { field in
                            Task { @MainActor in
                                editor.selectedAxisStopID = stop.id
                                editingStop = (stop.id, field)
                            }
                        },
                        onEndEdit: { scheduleClearEdit() },
                        onRegisterTabNavigation: { handler in
                            registerTabNavigation(for: stop.id, handler: handler)
                        },
                        onTabForwardFromValue: {
                            scheduleEditingStop(stopID: stop.id, field: .name)
                        },
                        onTabForwardFromName: {
                            advanceEditForward(axis: axis, afterStopID: stop.id)
                        },
                        onTabBackwardFromName: {
                            scheduleEditingStop(stopID: stop.id, field: .value)
                        },
                        onTabBackwardFromValue: {
                            advanceEditBackward(axis: axis, beforeStopID: stop.id)
                        },
                        onRemove: { editor.removeAxisStop(axisTag: axis.tag, stopID: stop.id) },
                        onCommitValue: { editor.updateAxisStopValue(axisTag: axis.tag, stopID: stop.id, value: $0) },
                        onCommitName: { editor.updateAxisStopName(axisTag: axis.tag, stopID: stop.id, name: $0) },
                        onToggleElidable: { editor.toggleAxisStopElidable(axisTag: axis.tag, stopID: stop.id) }
                    )
                    .id(stop.id)
                }
            }

            if axis.role == .instance {
                Button {
                    addStopRequest = AddAxisStopRequest(axisTag: axis.tag)
                } label: {
                    Label("Add Stop", systemImage: "plus")
                        .font(StudioTypography.caption)
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
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
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

    private func displayNameBinding(for tag: String) -> Binding<String> {
        Binding(
            get: {
                editor.selectedFont?.axes.first(where: { $0.tag == tag })?.displayName
                    ?? editor.selectedFont?.axes.first(where: { $0.tag == tag })?.tag
                    ?? tag
            },
            set: { editor.updateAxisDisplayName(tag: tag, name: $0) }
        )
    }

    private func resetExpansion() {
        guard let font = editor.selectedFont else {
            expandedAxes = []
            return
        }
        expandedAxes = Set(
            font.axes.filter {
                $0.role == .instance || $0.isDesignRecordOnly || !$0.values.isEmpty
            }.map(\.tag)
        )
    }

    private func expandAxisContaining(stopID: String) {
        guard let font = editor.selectedFont else { return }
        for axis in font.axes where axis.values.contains(where: { $0.id == stopID }) {
            expandedAxes.insert(axis.tag)
            return
        }
    }

    private func scrollToAxisStop(scrollProxy: ScrollViewProxy, axisTag: String, stopID: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            expandedAxes = [axisTag]
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollProxy.scrollTo(axisTag, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.2)) {
                    scrollProxy.scrollTo(stopID, anchor: .center)
                }
            }
        }
    }

    private func gridFormulaText(_ plan: InstancePlan) -> String {
        let parts = plan.formula.parts.map(String.init).joined(separator: " × ")
        return "\(parts) = \(plan.formula.totalGenerated)"
    }

    private func scheduleEditingStop(stopID: String, field: StopEditField) {
        Task { @MainActor in
            editingStop = (stopID, field)
            editor.selectedAxisStopID = stopID
        }
    }

    private func scheduleClearEdit() {
        Task { @MainActor in
            editingStop = nil
            tabKeyMonitor?.stop()
            tabKeyMonitor = nil
            activeTabNavigation = nil
            activeTabStopID = nil
        }
    }

    private func registerTabNavigation(for stopID: String, handler: ((Bool) -> Void)?) {
        if let handler {
            guard editingStop?.id == stopID else { return }
            activeTabNavigation = handler
            activeTabStopID = stopID
            guard tabKeyMonitor == nil else { return }
            let monitor = TabKeyMonitor { shift in
                activeTabNavigation?(!shift)
            }
            monitor.start()
            tabKeyMonitor = monitor
        } else if activeTabStopID == stopID {
            activeTabNavigation = nil
            activeTabStopID = nil
        }
    }

    private func advanceEditForward(axis: AxisDefinition, afterStopID: String) {
        guard let font = editor.selectedFont else {
            scheduleClearEdit()
            return
        }

        let stops = axis.values
        if let index = stops.firstIndex(where: { $0.id == afterStopID }),
           index + 1 < stops.count {
            let next = stops[index + 1]
            scheduleEditingStop(stopID: next.id, field: .value)
            return
        }

        guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axis.tag }) else {
            scheduleClearEdit()
            return
        }

        for nextAxis in font.axes[(axisIndex + 1)...] where !nextAxis.values.isEmpty {
            let first = nextAxis.values[0]
            Task { @MainActor in
                expandedAxes.insert(nextAxis.tag)
                editingStop = (first.id, .value)
                editor.selectedAxisStopID = first.id
            }
            return
        }

        scheduleClearEdit()
    }

    private func advanceEditBackward(axis: AxisDefinition, beforeStopID: String) {
        guard let font = editor.selectedFont else { return }

        let stops = axis.values
        if let index = stops.firstIndex(where: { $0.id == beforeStopID }),
           index > 0 {
            let previous = stops[index - 1]
            scheduleEditingStop(stopID: previous.id, field: .name)
            return
        }

        guard let axisIndex = font.axes.firstIndex(where: { $0.tag == axis.tag }),
              axisIndex > 0 else {
            return
        }

        for previousAxis in font.axes[..<axisIndex].reversed() where !previousAxis.values.isEmpty {
            let last = previousAxis.values[previousAxis.values.count - 1]
            Task { @MainActor in
                expandedAxes.insert(previousAxis.tag)
                editingStop = (last.id, .name)
                editor.selectedAxisStopID = last.id
            }
            return
        }
    }
}

// MARK: - Axis header

private struct AxisTreeAxisHeader: View {
    let axis: AxisDefinition
    let isExpanded: Bool
    var hasConflict: Bool = false
    @Binding var isInstanceAxis: Bool
    let onToggleExpansion: () -> Void
    var onResolveConflict: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(StudioTypography.meta)
                    .foregroundStyle(StudioColors.warningForeground)
                    .help("Naming conflict on this axis")
            }

            StudioTagPill(text: axis.tag)
                .frame(width: AxisBlockLayout.tagColumnWidth, alignment: .leading)

            Button(action: onToggleExpansion) {
                HStack(spacing: AxisBlockLayout.tagNameSpacing) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(axis.displayName ?? axis.tag)
                                .font(StudioTypography.body)
                                .lineLimit(1)
                            StudioDisclosureChevron(isExpanded: isExpanded)
                        }

                        if axis.isDesignRecordOnly {
                            Text("No fvar scale")
                                .font(StudioTypography.meta)
                                .foregroundStyle(.secondary)
                        } else if let range = axisRangeText {
                            Text(range)
                                .font(StudioTypography.meta)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(axis.isDesignRecordOnly
                ? "STAT design axis — edit the axis label and stop names below."
                : "Expand axis stops")

            Spacer(minLength: 4)

            if hasConflict, let onResolveConflict {
                Button("Resolve", action: onResolveConflict)
                    .font(StudioTypography.meta)
                    .controlSize(.small)
                    .help("Open conflict resolver for this axis")
            }

            HStack(spacing: 6) {
                if axis.isDesignRecordOnly {
                    StudioTagPill(text: "STAT", compact: true)
                        .help("Registered in STAT DesignAxisRecord only")
                }

                stopCountBadge
                    .fixedSize(horizontal: true, vertical: false)

                if !axis.isDesignRecordOnly {
                    Toggle("Instance axis", isOn: $isInstanceAxis)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help(
                            "When on, stops on this axis generate named instances. "
                                + "When off, the axis stays at its default value for every instance."
                        )
                        .accessibilityLabel("Instance axis")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stopCountBadge: some View {
        let count: Int
        let help: String
        if axis.isDesignRecordOnly {
            count = axis.values.count
            help = "\(count) STAT axis value\(count == 1 ? "" : "s") on this design axis"
        } else {
            count = isInstanceAxis ? axis.values.count : 0
            help = isInstanceAxis
                ? "\(axis.values.count) stops in the instance grid formula"
                : "Not in the instance grid (contributes ×0)"
        }
        return StudioCountBadge(
            text: "\(count)",
            highlighted: axis.isDesignRecordOnly || isInstanceAxis,
            fixedWidth: AxisBlockLayout.stopCountBadgeWidth,
            help: help
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

// MARK: - Design record axis label

private struct DesignRecordAxisLabelRow: View {
    let tag: String
    @Binding var displayName: String

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: AxisBlockLayout.removeGutterWidth)

            Text("Label")
                .font(StudioTypography.columnLabel)
                .foregroundStyle(.tertiary)
                .frame(width: AxisBlockLayout.valueColumnWidth, alignment: .trailing)

            StudioTextField(
                placeholder: tag,
                text: $displayName,
                font: StudioTypography.bodyMedium,
                rowHeight: StudioFieldMetrics.listRowMinHeight
            )
            .padding(.leading, AxisBlockLayout.nameGap)
            .help("STAT DesignAxisRecord axis label (AxisNameID)")
        }
        .padding(.horizontal, AxisBlockLayout.rowHorizontalPadding)
        .padding(.bottom, 2)
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

    /// Fixed width for stop-count badge so instance toggles align across axes (1–3 digits).
    static let stopCountBadgeWidth: CGFloat = 32

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
        .padding(.bottom, 1)
    }
}

// MARK: - Stop row

private struct AxisTreeStopRow: View {
    let axisTag: String
    let stop: AxisValue
    let isSelected: Bool
    let editingField: StopEditField?
    let showElidable: Bool
    var allowsRemove: Bool = true
    var valueEditable: Bool = true
    let isElidable: Bool
    let onSelect: () -> Void
    let onBeginEdit: (StopEditField) -> Void
    let onEndEdit: () -> Void
    let onRegisterTabNavigation: (((Bool) -> Void)?) -> Void
    let onTabForwardFromValue: () -> Void
    let onTabForwardFromName: () -> Void
    let onTabBackwardFromName: () -> Void
    let onTabBackwardFromValue: () -> Void
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
        .frame(minHeight: StudioFieldMetrics.listRowMinHeight)
        .padding(.horizontal, AxisBlockLayout.rowHorizontalPadding)
        .padding(.vertical, StudioSpacing.instanceRowVertical)
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
            if let field {
                onRegisterTabNavigation { forward in
                    navigateTab(forward: forward)
                }
                Task { @MainActor in
                    focusedField = field
                }
            } else {
                onRegisterTabNavigation(nil)
                focusedField = nil
            }
        }
        .onKeyPress(.escape) {
            guard editingField != nil else { return .ignored }
            commitCurrentEdit()
            onEndEdit()
            return .handled
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

            if allowsRemove, isHovered {
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
        Group {
            valueColumnContent
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var nameColumn: some View {
        Group {
            nameColumnContent
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var valueColumnContent: some View {
        if editingField == .value {
            StudioInlineTextField(
                placeholder: "Value",
                text: $editingValue,
                font: StudioTypography.monoValue,
                foreground: StudioColors.axisValue,
                rowHeight: StudioFieldMetrics.listRowMinHeight,
                alignment: .trailing,
                onSubmit: { navigateTab(forward: true) }
            )
            .focused($focusedField, equals: .value)
        } else if valueEditable {
            staticValueLabel
                .gesture(clickGesture(for: .value))
        } else {
            staticValueLabel
                .gesture(selectOnlyGesture)
        }
    }

    private var staticValueLabel: some View {
        Text(StudioFormatting.axisValue(stop.value))
            .font(StudioTypography.monoValue)
            .foregroundStyle(StudioColors.axisValue)
            .frame(maxWidth: .infinity, minHeight: StudioFieldMetrics.listRowMinHeight, alignment: .trailing)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var nameColumnContent: some View {
        if editingField == .name {
            StudioInlineTextField(
                placeholder: "Stop name",
                text: $editingName,
                font: StudioTypography.bodyMedium,
                rowHeight: StudioFieldMetrics.listRowMinHeight,
                onSubmit: {
                    commitName()
                    navigateTab(forward: true)
                }
            )
            .focused($focusedField, equals: .name)
        } else {
            Text(stop.name)
                .font(StudioTypography.bodyMedium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: StudioFieldMetrics.listRowMinHeight, alignment: .leading)
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

    private var selectOnlyGesture: some Gesture {
        TapGesture(count: 1)
            .onEnded {
                selectTask?.cancel()
                onSelect()
            }
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
        guard !AxisCoordinate.valuesEqual(value, stop.value) else { return }
        let commit = onCommitValue
        Task { @MainActor in
            commit(value)
        }
    }

    private func commitName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            syncDrafts()
            return
        }
        guard trimmed != stop.name else { return }
        let commit = onCommitName
        Task { @MainActor in
            commit(trimmed)
        }
    }

    private func navigateTab(forward: Bool) {
        guard editingField != nil else { return }

        switch (editingField, forward) {
        case (.value, true):
            commitValue()
            onTabForwardFromValue()
        case (.name, true):
            commitName()
            onTabForwardFromName()
        case (.name, false):
            onTabBackwardFromName()
        case (.value, false):
            commitValue()
            onTabBackwardFromValue()
        case (nil, _):
            break
        }
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

// MARK: - Add stop sheet

private struct AddAxisStopSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let onComplete: () -> Void

    @State private var valueText = ""
    @State private var nameText = ""
    @State private var tabKeyMonitor: TabKeyMonitor?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case value
        case name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Add Stop")
                .font(StudioTypography.emphasis)

            Text(axisSubtitle)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                StudioTextField(
                    placeholder: "Value",
                    text: $valueText,
                    font: StudioTypography.monoValue,
                    rowHeight: StudioFieldMetrics.monoValueRowHeight
                )
                .focused($focusedField, equals: .value)
                .onSubmit { focusedField = .name }

                StudioTextField(
                    placeholder: "Name",
                    text: $nameText,
                    rowHeight: StudioFieldMetrics.bodyRowHeight
                )
                .focused($focusedField, equals: .name)
                .onSubmit(addStopIfValid)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Add Stop") {
                    addStopIfValid()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            let suggested = editor.suggestedNewStopValue(for: axis)
            valueText = StudioFormatting.axisValue(suggested)
            nameText = "Name"
            focusedField = .value
            let monitor = TabKeyMonitor { shift in
                if shift {
                    if focusedField == .name {
                        focusedField = .value
                    }
                } else if focusedField == .value {
                    focusedField = .name
                }
            }
            monitor.start()
            tabKeyMonitor = monitor
        }
        .onDisappear {
            tabKeyMonitor?.stop()
            tabKeyMonitor = nil
        }
    }

    private var axisSubtitle: String {
        let title = axis.displayName ?? axis.tag
        if let min = axis.min, let max = axis.max {
            let minText = StudioFormatting.axisValue(min)
            let maxText = StudioFormatting.axisValue(max)
            if let defaultValue = axis.default {
                return "\(title) · allowed \(minText) – \(StudioFormatting.axisValue(defaultValue)) – \(maxText)"
            }
            return "\(title) · allowed \(minText) – \(maxText)"
        }
        return title
    }

    private var parsedValue: Double? {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var trimmedName: String {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        guard let value = parsedValue else {
            return valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "Enter a valid number."
        }
        if trimmedName.isEmpty {
            return "Name is required."
        }
        return editor.validateAxisStopValue(value, for: axis)
    }

    private var canAdd: Bool {
        guard let value = parsedValue, !trimmedName.isEmpty else { return false }
        return editor.validateAxisStopValue(value, for: axis) == nil
    }

    private func addStopIfValid() {
        guard canAdd, let value = parsedValue else { return }
        let name = trimmedName
        let tag = axis.tag
        onComplete()
        dismiss()
        Task { @MainActor in
            editor.insertAxisStop(axisTag: tag, value: value, name: name)
        }
    }
}

// MARK: - Tab key monitor

/// Intercepts Tab before AppKit text fields resign first responder (SwiftUI onKeyPress is too late).
@MainActor
private final class TabKeyMonitor {
    private var monitor: Any?
    private let handler: (Bool) -> Void

    init(handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func start() {
        guard monitor == nil else { return }
        let tabHandler = handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 48 else { return event }
            tabHandler(event.modifierFlags.contains(.shift))
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
