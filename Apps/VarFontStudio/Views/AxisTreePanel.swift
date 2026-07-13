import AppKit
import SwiftUI
import VarFontCore

private enum StopEditField: Equatable {
    case min
    case pin
    case max
    case name
}

private struct AddAxisStopRequest: Identifiable {
    let axisTag: String
    var id: String { axisTag }
}

private struct FillStopsRequest: Identifiable {
    let axisTag: String
    var id: String { axisTag }
}

private struct StopFormatChangeRequest: Identifiable {
    let axisTag: String
    let stopID: String
    var id: String { stopID }
}

// MARK: - Axis block state spec
//
// Reachable axis-block states — check new UI against this table before bolting on another branch.
// Dimensions: lane × expanded × isDesignRecordOnly × values.isEmpty × hasConflict × hasAxisWarning × isInstanceAxis
//
// Collapsed (expanded = N): header only — subtitle always visible; table / Add Stop hidden.
//
// | Lane        | DesignRec | Empty | Inst | Header subtitle (merged)              | Table | Add Stop |
// |-------------|-----------|-------|------|---------------------------------------|-------|----------|
// | variation   | N         | N     | Y    | min – def – max                       | YES   | YES      |
// | variation   | N         | Y     | Y    | min – def – max                       | empty | YES      |
// | pinned      | N         | N     | N    | min – def – max · Pinned at X         | YES   | NO       |
// | pinned      | N         | Y     | N    | min – def – max · Pinned at X         | empty | NO       |
// | registration| Y         | N     | —    | No fvar scale · {stop}▾              | YES   | NO       |
// | registration| Y         | Y     | —    | No fvar scale · {stop?}▾             | empty | NO       |
// | registration| N         | *     | —    | No fvar scale [· {stop?}▾]           | *     | NO       |
//
// hasConflict → warning icon + Resolve in header (all lanes). hasAxisWarning → warning icon in header;
// axis-scoped plan warnings do not repeat in the scroll banner (rollup only when 2+ axes need attention).
// Badge: highlighted count = in-grid stops (variation) or STAT values (registration); muted 0 = toggled off (pinned).

/// Plan-warning codes surfaced inline on the axis header (not repeated per-message in the scroll banner).
private enum AxisTreePlanWarningCodes {
    static let axisInline: Set<String> = [
        "registration_mismatch",
        "registration_value_missing",
        "orphan_stat_link",
        "ital_value_name_mismatch",
        "ital_format1_upgrade",
        "wght_format1_upgrade",
        "fvar_missing_from_stat",
        "stat_missing_from_fvar",
        "multiple_elidable",
        "empty_instance_axis",
    ]
}

/// Vertical rhythm inside an expanded axis block — one constant per relationship.
private enum AxisDetailSpacing {
    /// Design-record label row → stop table or empty-state message.
    static let metadataToTableGap: CGFloat = StudioSpacing.rowGap
    /// Column header + first data row read as one unit.
    static let tableHeaderToFirstRowGap: CGFloat = 1
    /// Last stop row → Add Stop CTA.
    static let lastStopToAddButtonGap: CGFloat = StudioSpacing.controlGap
}

struct AxisTreePanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @State private var expandedAxes: Set<String> = []
    @State private var editingStop: (id: String, field: StopEditField)?
    @State private var addStopRequest: AddAxisStopRequest?
    @State private var fillStopsRequest: FillStopsRequest?
    @State private var formatChangeRequest: StopFormatChangeRequest?
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
                        Button("Push Axis Tree") {
                            editor.requestPushMasterAxisTree()
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

            if editor.selectedFont != nil {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        gridSummaryContent
                        axesContent(scrollProxy: scrollProxy)
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
            } else {
                ContentUnavailableView(
                    "No Axis Tree",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Select a file to view its axis tree.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .sheet(item: $fillStopsRequest) { request in
            if let axis = editor.selectedFont?.axes.first(where: { $0.tag == request.axisTag }) {
                FillAxisStopsSheet(axis: axis) {
                    fillStopsRequest = nil
                }
                .environmentObject(editor)
                .id(request.axisTag)
            }
        }
        .sheet(item: $formatChangeRequest) { request in
            if let axis = editor.selectedFont?.axes.first(where: { $0.tag == request.axisTag }),
               let stop = axis.values.first(where: { $0.id == request.stopID }) {
                ChangeAxisStopFormatSheet(axis: axis, stop: stop) {
                    formatChangeRequest = nil
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
                studioSummaryRow("Generated", value: "\(plan.formula.totalGenerated)")
            }
            .padding(.bottom, StudioSpacing.sectionGap)
        }
    }

    private func studioSummaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(StudioTypography.bodyMedium)
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
    private func planWarningsBand(scrollProxy: ScrollViewProxy) -> some View {
        let issueCount = editor.reviewIssueCount
        let infoWarnings = informationalPlanWarningsForBand

        if issueCount > 0 || !infoWarnings.isEmpty {
            VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
                if issueCount > 0 {
                    StudioConflictAlert(
                        message: issueCount == 1 ? "1 issue to review" : "\(issueCount) issues to review",
                        actionTitle: "Review issues…"
                    ) {
                        editor.startReviewSession()
                    }
                }

                ForEach(Array(infoWarnings.enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .top, spacing: StudioSpacing.controlGap) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(StudioTypography.meta)
                            .foregroundStyle(StudioColors.warningForeground)
                            .padding(.top, 1)
                        Text(warning.message)
                            .font(StudioTypography.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: StudioSpacing.controlGap)
                        if warning.code == "duplicate_composed_name" {
                            Button("Show in list…") {
                                layout.showInstances = true
                                if let name = warning.name {
                                    editor.showDuplicateInstances(matchingName: name)
                                } else {
                                    editor.showAllDuplicateInstances()
                                }
                            }
                            .font(StudioTypography.meta)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        if PlanIssueCodes.resolvable.contains(warning.code), issueCount > 0 {
                            Button("Review…") {
                                editor.startReviewSession(jumpingTo: warning)
                                if let axis = warning.axis {
                                    focusAxis(axis, scrollProxy: scrollProxy)
                                }
                            }
                            .font(StudioTypography.meta)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(StudioColors.warningFill, in: RoundedRectangle(cornerRadius: StudioRadius.row))
            .padding(.bottom, StudioSpacing.controlGap)
        }
    }

    private var informationalPlanWarningsForBand: [PlanWarning] {
        summarizedComposedNameWarnings(editor.informationalPlanWarnings())
    }

    private func summarizedComposedNameWarnings(_ warnings: [PlanWarning]) -> [PlanWarning] {
        let duplicateComposed = warnings.filter { $0.code == "duplicate_composed_name" }
        let other = warnings.filter { $0.code != "duplicate_composed_name" }
        guard duplicateComposed.count > 3 else { return warnings }
        let summary = PlanWarning(
            code: "duplicate_composed_name",
            message: "\(duplicateComposed.count) composed names are duplicated.",
            hint: duplicateComposed[0].hint
        )
        return other + [summary]
    }

    private func axisPlanWarnings(for tag: String) -> [PlanWarning] {
        editor.instancePlan?.warnings.filter {
            $0.axis == tag && AxisTreePlanWarningCodes.axisInline.contains($0.code)
        } ?? []
    }

    private func focusAxis(_ tag: String, scrollProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            expandedAxes.insert(tag)
            return ()
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollProxy.scrollTo(tag, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func axesContent(scrollProxy: ScrollViewProxy) -> some View {
        planWarningsBand(scrollProxy: scrollProxy)

        if editor.unresolvedAxisConflictCount > 0, editor.reviewIssueCount == 0 {
            StudioConflictAlert(
                message: conflictAlertMessage,
                actionTitle: "Resolve…"
            ) {
                editor.presentFirstConflictResolver()
            }
            .padding(.bottom, StudioSpacing.controlGap)
        }

        if let font = editor.selectedFont {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(font.axes.enumerated()), id: \.element.id) { index, axis in
                    if index > 0 {
                        Divider()
                            .padding(.vertical, StudioSpacing.rowGap)
                    }
                    axisBlock(axis)
                        .id(axis.tag)
                }
            }

            if !font.compoundStatValues.isEmpty {
                CombinationStylesSection(compounds: font.compoundStatValues, axes: font.axes)
                    .padding(.top, StudioSpacing.sectionGap)
            }
        }
    }

    @ViewBuilder
    private func axisBlock(_ axis: AxisDefinition) -> some View {
        let isExpanded = expandedAxes.contains(axis.tag)
        let resolvableWarnings = axisPlanWarnings(for: axis.tag)
            .filter { PlanIssueCodes.resolvable.contains($0.code) }

        VStack(alignment: .leading, spacing: 0) {
            AxisTreeAxisHeader(
                axis: axis,
                isExpanded: isExpanded,
                hasConflict: editor.bundle(for: axis.tag) != nil,
                axisWarnings: axisPlanWarnings(for: axis.tag),
                resolvablePlanWarnings: resolvableWarnings,
                fileRegistrationLabel: axis.lane == .registration ? registrationLabel(for: axis) : nil,
                registrationStops: axis.lane == .registration ? axis.values : [],
                selectedRegistrationStopID: registrationStopID(for: axis),
                onSelectRegistrationStop: axis.lane == .registration ? { stopID in
                    guard let font = editor.selectedFont,
                          let stop = axis.values.first(where: { $0.id == stopID }) else { return }
                    editor.setFileStatRegistration(tag: axis.tag, value: stop.value, forFontID: font.id)
                } : nil,
                isInstanceAxis: instanceAxisBinding(for: axis.tag),
                onToggleExpansion: { toggleExpansion(for: axis.tag) },
                onResolveConflict: {
                    editor.presentConflictResolver(for: axis.tag)
                },
                onReviewPlanIssue: {
                    editor.presentFirstResolvablePlanIssue(on: axis.tag)
                }
            )

            if isExpanded {
                axisDetail(axis)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Axis detail

    private func axisActionButtonLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(StudioTypography.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.tertiary)
            }
    }

    @ViewBuilder
    private func axisDetail(_ axis: AxisDefinition) -> some View {
        let showElidable = axis.role == .instance || axis.lane == .registration

        VStack(alignment: .leading, spacing: 0) {
            if axis.values.isEmpty {
                Text(axis.isDesignRecordOnly
                    ? "No STAT axis values on this design axis"
                    : "No STAT stops on this axis")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                AxisStopTableHeader(
                    showElidable: showElidable,
                    showDefaultMark: axis.hasFvarScale,
                    showRemoveSlot: !axis.isDesignRecordOnly
                )
                .padding(.bottom, AxisDetailSpacing.tableHeaderToFirstRowGap)

                ForEach(axis.values) { stop in
                    axisStopRow(axis: axis, stop: stop, showElidable: showElidable)
                        .id(stop.id)
                }
            }

            if axis.role == .instance {
                let showFill = AxisStopFillPlanner.supportsFill(axis)
                HStack(spacing: StudioSpacing.controlGap) {
                    Button {
                        addStopRequest = AddAxisStopRequest(axisTag: axis.tag)
                    } label: {
                        axisActionButtonLabel(title: "Add Stop", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 0, maxWidth: showFill ? .infinity : nil)

                    if showFill {
                        Button {
                            fillStopsRequest = FillStopsRequest(axisTag: axis.tag)
                        } label: {
                            axisActionButtonLabel(
                                title: "Fill stops…",
                                systemImage: "square.grid.3x1.folder.badge.plus"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .help(
                            axis.values.isEmpty
                                ? "Evenly space or interval-fill stops across this axis's range."
                                : "Replace this axis's stops with an evenly spaced or interval fill. Reopen anytime to tweak."
                        )
                    }
                }
                .padding(.top, AxisDetailSpacing.lastStopToAddButtonGap)
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

    private func registrationLabel(for axis: AxisDefinition) -> String? {
        guard let font = editor.selectedFont,
              let value = font.fileStatRegistration[axis.tag],
              let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else {
            return axis.values.first?.name
        }
        return stop.name
    }

    private func registrationStopID(for axis: AxisDefinition) -> String? {
        guard let font = editor.selectedFont,
              let value = font.fileStatRegistration[axis.tag],
              let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else {
            return axis.values.first?.id
        }
        return stop.id
    }

    private func isRegistrationStop(_ stop: AxisValue, axis: AxisDefinition) -> Bool {
        guard axis.lane == .registration,
              let font = editor.selectedFont,
              let value = font.fileStatRegistration[axis.tag],
              let registered = AxisCoordinate.matchingStop(in: axis.values, coordinate: value) else {
            return false
        }
        return registered.id == stop.id
    }

    private func linkedTargetName(for stop: AxisValue, in axis: AxisDefinition) -> String? {
        guard stop.statFormat == 3, let linkedValue = stop.linkedValue else { return nil }
        if let target = axis.values.first(where: {
            $0.id != stop.id && AxisCoordinate.valuesEqual($0.value, linkedValue)
        }) {
            return target.name
        }
        return StudioFormatting.axisValue(linkedValue)
    }

    private func axisStopRow(
        axis: AxisDefinition,
        stop: AxisValue,
        showElidable: Bool
    ) -> some View {
        let isFvarDefault = axis.hasFvarScale
            && axis.default.map { AxisCoordinate.valuesEqual($0, stop.value) } == true
        return AxisTreeStopRow(
            stop: stop,
            linkedTargetName: linkedTargetName(for: stop, in: axis),
            isRegistrationStop: isRegistrationStop(stop, axis: axis),
            linkTargetCandidates: axis.values.filter { $0.id != stop.id },
            isSelected: editor.selectedAxisStopID == stop.id,
            editingField: editingStop?.id == stop.id ? editingStop?.field : nil,
            showElidable: showElidable,
            showDefaultMark: axis.hasFvarScale,
            isFvarDefault: isFvarDefault,
            allowsRemove: !axis.isDesignRecordOnly,
            valueEditable: axis.hasFvarScale || axis.isDesignRecordOnly,
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
            onChangeFormat: {
                formatChangeRequest = StopFormatChangeRequest(axisTag: axis.tag, stopID: stop.id)
            },
            onRegisterTabNavigation: { handler in
                registerTabNavigation(for: stop.id, handler: handler)
            },
            onTabForwardFromLastField: {
                advanceEditForward(axis: axis, afterStopID: stop.id)
            },
            onTabBackwardFromFirstField: {
                advanceEditBackward(axis: axis, beforeStopID: stop.id)
            },
            onRemove: { editor.removeAxisStop(axisTag: axis.tag, stopID: stop.id) },
            onCommitPin: { editor.updateAxisStopValue(axisTag: axis.tag, stopID: stop.id, value: $0) },
            onCommitMin: { editor.updateAxisStopRangeMin(axisTag: axis.tag, stopID: stop.id, rangeMin: $0) },
            onCommitMax: { editor.updateAxisStopRangeMax(axisTag: axis.tag, stopID: stop.id, rangeMax: $0) },
            onCommitName: { editor.updateAxisStopName(axisTag: axis.tag, stopID: stop.id, name: $0) },
            onToggleElidable: { editor.toggleAxisStopElidable(axisTag: axis.tag, stopID: stop.id) },
            onSelectLinkTarget: { targetID in
                editor.updateAxisStopLinkedTarget(axisTag: axis.tag, stopID: stop.id, linkTargetStopID: targetID)
            }
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
            expandedAxes.insert(axisTag)
            return ()
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

    private func firstEditableField(for stop: AxisValue, axis: AxisDefinition) -> StopEditField {
        if axis.hasFvarScale { return .pin }
        return .name
    }

    private func lastEditableField(for stop: AxisValue, axis: AxisDefinition) -> StopEditField {
        .name
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
            scheduleEditingStop(stopID: next.id, field: firstEditableField(for: next, axis: axis))
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
                editingStop = (first.id, firstEditableField(for: first, axis: nextAxis))
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
            scheduleEditingStop(stopID: previous.id, field: lastEditableField(for: previous, axis: axis))
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
                editingStop = (last.id, lastEditableField(for: last, axis: previousAxis))
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

    private var lane: AxisLane { axis.lane }

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
        HStack(spacing: 8) {
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help("Hide this axis from user-facing controls (fvar HIDDEN_AXIS flag).")
            }

            VStack(alignment: .leading, spacing: 1) {
                Button(action: onToggleExpansion) {
                    HStack(spacing: 4) {
                        Text(axis.displayName ?? axis.tag)
                            .font(StudioTypography.body)
                            .lineLimit(1)
                        StudioDisclosureChevron(isExpanded: isExpanded)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(lane == .registration
                    ? "STAT design axis — edit the axis label and stop names below."
                    : "Expand axis stops")

                // Registration stop menu must stay outside the expand button.
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

            HStack(spacing: 6) {
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
                                + "Registration axes never use this toggle."
                        )
                        .accessibilityLabel("Instance axis")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var registrationSubtitle: some View {
        HStack(spacing: 4) {
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
}

// MARK: - Axis block layout

/// Shared horizontal metrics for the two-row adaptive stop table (layout K).
private enum AxisBlockLayout {
    static let tagColumnWidth: CGFloat = 34
    static let tagNameSpacing: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 6

    /// Nests stop rows under the axis header without reserving remove-button space.
    static let stopIndentWidth: CGFloat = 18
    /// fvar-default marker column (square) before Fmt.
    static let defaultMarkWidth: CGFloat = 22
    /// Breathing room between the fvar-default marker and the Fmt badge.
    static let defaultMarkTrailingGap: CGFloat = 4
    static let fmtColumnWidth: CGFloat = 36
    static let valueColumnWidth: CGFloat = 52
    static let nameGap: CGFloat = 6
    static let elidableWidth: CGFloat = 26

    static func nameLeading(showDefaultMark: Bool) -> CGFloat {
        stopIndentWidth
            + (showDefaultMark ? defaultMarkWidth + defaultMarkTrailingGap : 0)
            + fmtColumnWidth
            + valueColumnWidth
            + nameGap
    }

    static func rangeSublineLeading(showDefaultMark: Bool) -> CGFloat {
        nameLeading(showDefaultMark: showDefaultMark)
    }

    static let stopCountBadgeWidth: CGFloat = 32
    static let removeButtonSize: CGFloat = StudioIncludeCheckbox.size
    /// Real reserved trailing column for the hover-remove button — small on
    /// purpose (button-sized, not a full column like Fmt/Value/Elid), but a
    /// genuine layout slot so the row's own background contains it without
    /// needing a separately hand-tuned offset to agree with it.
    static let removeSlotWidth: CGFloat = removeButtonSize + 4
    static let removeSlotLeadingGap: CGFloat = 6
}

// MARK: - Stop table header

private struct AxisStopTableHeader: View {
    let showElidable: Bool
    var showDefaultMark: Bool = false
    var showRemoveSlot: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: AxisBlockLayout.stopIndentWidth)

            if showDefaultMark {
                Color.clear
                    .frame(width: AxisBlockLayout.defaultMarkWidth, alignment: .leading)
                    .padding(.trailing, AxisBlockLayout.defaultMarkTrailingGap)
            }

            Text("Fmt")
                .font(StudioTypography.columnLabel)
                .foregroundStyle(.tertiary)
                .frame(width: AxisBlockLayout.fmtColumnWidth, alignment: .leading)

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
                Text("Elid")
                    .font(StudioTypography.columnLabel)
                    .foregroundStyle(.tertiary)
                    .frame(width: AxisBlockLayout.elidableWidth, alignment: .center)
                    .help("Omit this stop from the composed style name when it is the default choice")
            }

            // Mirrors AxisTreeStopRow's removeSlot exactly — same width, same
            // leading gap — so Name/Elid stay aligned with the rows beneath
            // this header instead of drifting by however wide that slot is.
            if showRemoveSlot {
                Color.clear
                    .frame(width: AxisBlockLayout.removeSlotWidth)
                    .padding(.leading, AxisBlockLayout.removeSlotLeadingGap)
            }
        }
        .padding(.horizontal, AxisBlockLayout.rowHorizontalPadding)
        .padding(.bottom, 2)
    }
}

// MARK: - Stop row

private struct AxisTreeStopRow: View {
    let stop: AxisValue
    var linkedTargetName: String?
    var isRegistrationStop: Bool = false
    var linkTargetCandidates: [AxisValue] = []
    let isSelected: Bool
    let editingField: StopEditField?
    let showElidable: Bool
    var showDefaultMark: Bool = false
    var isFvarDefault: Bool = false
    var allowsRemove: Bool = true
    var valueEditable: Bool = true
    let isElidable: Bool
    let onSelect: () -> Void
    let onBeginEdit: (StopEditField) -> Void
    let onEndEdit: () -> Void
    let onChangeFormat: () -> Void
    let onRegisterTabNavigation: (((Bool) -> Void)?) -> Void
    let onTabForwardFromLastField: () -> Void
    let onTabBackwardFromFirstField: () -> Void
    let onRemove: () -> Void
    let onCommitPin: (Double) -> Void
    let onCommitMin: (Double) -> Void
    let onCommitMax: (Double) -> Void
    let onCommitName: (String) -> Void
    let onToggleElidable: () -> Void
    var onSelectLinkTarget: ((String) -> Void)?

    @State private var isHovered = false
    @State private var editingMin = ""
    @State private var editingPin = ""
    @State private var editingMax = ""
    @State private var editingName = ""
    @State private var confirmRemove = false
    @State private var selectTask: Task<Void, Never>?
    @FocusState private var focusedField: StopEditField?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            primaryRow

            if stop.statFormat == 2 {
                format2RangeSubline
            }
        }
        .padding(.horizontal, AxisBlockLayout.rowHorizontalPadding)
        .padding(.vertical, StudioSpacing.instanceRowVertical)
        .background {
            StudioRowBackground(isSelected: isSelected, isHovered: isHovered)
                .padding(.leading, -AxisBlockLayout.rowHorizontalPadding)
        }
        .overlay(alignment: .leading) {
            if isRegistrationStop {
                RoundedRectangle(cornerRadius: 2)
                    .fill(StudioColors.registrationForeground.opacity(0.85))
                    .frame(width: 3)
                    .padding(.leading, 2)
            }
        }
        .onHover { isHovered = $0 }
        .onAppear { syncDrafts() }
        .onChange(of: stop.value) { _, _ in syncDrafts() }
        .onChange(of: stop.rangeMin) { _, _ in syncDrafts() }
        .onChange(of: stop.rangeMax) { _, _ in syncDrafts() }
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

    private var primaryRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Color.clear
                .frame(width: AxisBlockLayout.stopIndentWidth)

            defaultMarkCell

            StudioStatFormatBadge(format: stop.statFormat, action: onChangeFormat)
                .frame(width: AxisBlockLayout.fmtColumnWidth, alignment: .leading)

            valueCell
                .frame(width: AxisBlockLayout.valueColumnWidth, alignment: .trailing)

            nameColumn
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AxisBlockLayout.nameGap)

            if showElidable {
                StudioElidableRadio(isOn: isElidable, action: onToggleElidable)
                    .frame(width: AxisBlockLayout.elidableWidth)
            }

            // Real reserved column, not an overlay — sized to the button alone,
            // so it's contained by the row's own background automatically instead
            // of needing a separately hand-tuned offset/background pair to agree.
            removeSlot
        }
        .frame(minHeight: StudioFieldMetrics.listRowMinHeight)
    }

    @ViewBuilder
    private var defaultMarkCell: some View {
        if showDefaultMark {
            Group {
                if isFvarDefault {
                    Image(systemName: "d.square.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .help("fvar default coordinate")
                        .accessibilityLabel("fvar default")
                } else {
                    Color.clear
                }
            }
            .frame(width: AxisBlockLayout.defaultMarkWidth, alignment: .leading)
            .padding(.trailing, AxisBlockLayout.defaultMarkTrailingGap)
        }
    }

    @ViewBuilder
    private var removeSlot: some View {
        if allowsRemove {
            ZStack {
                if isHovered {
                    Button {
                        confirmRemove = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: AxisBlockLayout.removeButtonSize))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove stop")
                }
            }
            .frame(width: AxisBlockLayout.removeSlotWidth)
            .padding(.leading, AxisBlockLayout.removeSlotLeadingGap)
        }
    }

    @ViewBuilder
    private var valueCell: some View {
        Group {
            if editingField == .pin, valueEditable {
                StudioInlineTextField(
                    placeholder: "Value",
                    text: $editingPin,
                    font: StudioTypography.monoValue,
                    foreground: StudioColors.axisValue,
                    rowHeight: StudioFieldMetrics.listRowMinHeight,
                    alignment: .trailing,
                    onSubmit: commitAndEndEdit,
                    onCancel: cancelInlineEdit
                )
                .focused($focusedField, equals: .pin)
            } else if valueEditable {
                Text(StudioFormatting.axisValue(stop.value))
                    .font(StudioTypography.monoValue)
                    .foregroundStyle(StudioColors.axisValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: StudioFieldMetrics.listRowMinHeight, alignment: .trailing)
                    .contentShape(Rectangle())
                    .gesture(clickGesture(for: .pin))
            } else {
                Text(StudioFormatting.axisValue(stop.value))
                    .font(StudioTypography.monoValue)
                    .foregroundStyle(StudioColors.axisValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: StudioFieldMetrics.listRowMinHeight, alignment: .trailing)
                    .contentShape(Rectangle())
                    .gesture(selectOnlyGesture)
            }
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var format2RangeSubline: some View {
        HStack(spacing: 4) {
            sublineLabel("min")
            sublineField(.min, value: stop.rangeMin, placeholder: "Min")
            sublineSeparator
            sublineLabel("nom")
            Text(StudioFormatting.axisValue(stop.value))
                .font(StudioTypography.monoMeta)
                .foregroundStyle(StudioColors.axisValue)
            sublineSeparator
            sublineLabel("max")
            sublineField(.max, value: stop.rangeMax, placeholder: "Max")
        }
        .padding(.leading, AxisBlockLayout.rangeSublineLeading(showDefaultMark: showDefaultMark))
        .padding(.bottom, 3)
    }

    private func sublineLabel(_ text: String) -> some View {
        Text(text)
            .font(StudioTypography.meta)
            .foregroundStyle(.tertiary)
    }

    private var sublineSeparator: some View {
        Text("·")
            .font(StudioTypography.meta)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func sublineField(_ field: StopEditField, value: Double?, placeholder: String) -> some View {
        if editingField == field, valueEditable {
            StudioInlineTextField(
                placeholder: placeholder,
                text: binding(for: field),
                font: StudioTypography.monoMeta,
                foreground: StudioColors.axisValue,
                rowHeight: StudioFieldMetrics.captionRowHeight,
                alignment: .trailing,
                onSubmit: commitAndEndEdit,
                onCancel: cancelInlineEdit
            )
            .frame(width: 44)
            .focused($focusedField, equals: field)
        } else if let value {
            if valueEditable {
                Text(StudioFormatting.axisValue(value))
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(StudioColors.axisValue)
                    .contentShape(Rectangle())
                    .gesture(clickGesture(for: field))
            } else {
                Text(StudioFormatting.axisValue(value))
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(StudioColors.axisValue)
                    .contentShape(Rectangle())
                    .gesture(selectOnlyGesture)
            }
        } else {
            Text("—")
                .font(StudioTypography.monoMeta)
                .foregroundStyle(.tertiary.opacity(0.45))
        }
    }

    private func binding(for field: StopEditField) -> Binding<String> {
        switch field {
        case .min: $editingMin
        case .pin: $editingPin
        case .max: $editingMax
        case .name: $editingName
        }
    }

    @ViewBuilder
    private var nameColumn: some View {
        Group {
            if editingField == .name {
                StudioInlineTextField(
                    placeholder: "Stop name",
                    text: $editingName,
                    font: StudioTypography.bodyMedium,
                    rowHeight: StudioFieldMetrics.listRowMinHeight,
                    onSubmit: commitAndEndEdit,
                    onCancel: cancelInlineEdit
                )
                .focused($focusedField, equals: .name)
            } else {
                HStack(spacing: 4) {
                    Text(stop.name)
                        .font(StudioTypography.bodyMedium)
                        .lineLimit(1)
                    if stop.statFormat == 3 {
                        if !linkTargetCandidates.isEmpty, let onSelectLinkTarget {
                            Menu {
                                ForEach(linkTargetCandidates) { target in
                                    Button {
                                        onSelectLinkTarget(target.id)
                                    } label: {
                                        if let linkedTargetName, target.name == linkedTargetName {
                                            Label(target.name, systemImage: "checkmark")
                                        } else {
                                            Text(target.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(StudioTypography.caption)
                                        .foregroundStyle(.tertiary)
                                    Text(linkedTargetName ?? "Link…")
                                        .font(StudioTypography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .menuStyle(.borderlessButton)
                        } else if let linkedTargetName {
                            Image(systemName: "link")
                                .font(StudioTypography.caption)
                                .foregroundStyle(.tertiary)
                            Text(linkedTargetName)
                                .font(StudioTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: StudioFieldMetrics.listRowMinHeight, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(clickGesture(for: .name))
            }
        }
        .transaction { $0.animation = nil }
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
        editingMin = stop.rangeMin.map(StudioFormatting.axisValue) ?? ""
        editingPin = StudioFormatting.axisValue(stop.value)
        editingMax = stop.rangeMax.map(StudioFormatting.axisValue) ?? ""
        editingName = stop.name
    }

    private func editableFields() -> [StopEditField] {
        if valueEditable, stop.statFormat == 2 {
            return [.pin, .min, .max, .name]
        }
        if valueEditable {
            return [.pin, .name]
        }
        return [.name]
    }

    private func commitCurrentEdit() {
        guard let editingField else { return }
        switch editingField {
        case .min: commitMin()
        case .pin: commitPin()
        case .max: commitMax()
        case .name: commitName()
        }
    }

    private func commitMin() {
        let trimmed = editingMin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed) else {
            syncDrafts()
            return
        }
        if let current = stop.rangeMin, AxisCoordinate.valuesEqual(value, current) { return }
        Task { @MainActor in onCommitMin(value) }
    }

    private func commitPin() {
        let trimmed = editingPin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed) else {
            syncDrafts()
            return
        }
        guard !AxisCoordinate.valuesEqual(value, stop.value) else { return }
        Task { @MainActor in onCommitPin(value) }
    }

    private func commitMax() {
        let trimmed = editingMax.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed) else {
            syncDrafts()
            return
        }
        if let current = stop.rangeMax, AxisCoordinate.valuesEqual(value, current) { return }
        Task { @MainActor in onCommitMax(value) }
    }

    private func commitName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            syncDrafts()
            return
        }
        guard trimmed != stop.name else { return }
        Task { @MainActor in onCommitName(trimmed) }
    }

    private func navigateTab(forward: Bool) {
        guard let editingField else { return }
        let fields = editableFields()
        guard let index = fields.firstIndex(of: editingField) else { return }

        if forward {
            commitCurrentEdit()
            if index + 1 < fields.count {
                onBeginEdit(fields[index + 1])
            } else {
                onTabForwardFromLastField()
            }
        } else if index > 0 {
            commitCurrentEdit()
            onBeginEdit(fields[index - 1])
        } else {
            onTabBackwardFromFirstField()
        }
    }

    /// Return commits the current field and leaves edit mode — does not advance like Tab.
    private func commitAndEndEdit() {
        commitCurrentEdit()
        onEndEdit()
    }

    private func cancelInlineEdit() {
        syncDrafts()
        onEndEdit()
    }
}

// MARK: - Add stop sheet

private struct AddAxisStopSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let onComplete: () -> Void

    @State private var statFormat = 1
    @State private var pinText = ""
    @State private var minText = ""
    @State private var maxText = ""
    @State private var nameText = ""
    @State private var linkTargetID: String?
    @State private var tabKeyMonitor: TabKeyMonitor?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case pin, min, max, name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Add Stop")
                .font(StudioTypography.emphasis)

            Text(axisSubtitle)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)

            Picker("STAT format", selection: $statFormat) {
                Text("Format 1 — static").tag(1)
                Text("Format 2 — range").tag(2)
                Text("Format 3 — linked").tag(3)
            }
            .pickerStyle(.menu)
            .onChange(of: statFormat) { _, _ in seedDefaults() }

            VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                formatFields
                StudioTextField(
                    placeholder: "Name",
                    text: $nameText,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    onSubmit: addStopIfValid
                )
                .focused($focusedField, equals: .name)
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
        .frame(width: 360)
        .onAppear {
            seedDefaults()
            nameText = "Name"
            focusedField = .pin
            let monitor = TabKeyMonitor { shift in
                guard let focusedField else { return }
                let order = fieldOrder
                guard let index = order.firstIndex(of: focusedField) else { return }
                if shift {
                    if index > 0 { self.focusedField = order[index - 1] }
                } else if index + 1 < order.count {
                    self.focusedField = order[index + 1]
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

    @ViewBuilder
    private var formatFields: some View {
        switch statFormat {
        case 2:
            StudioTextField(
                placeholder: "Min",
                text: $minText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .min) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .min)
            StudioTextField(
                placeholder: "Nominal (Pin)",
                text: $pinText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .pin) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .pin)
            StudioTextField(
                placeholder: "Max",
                text: $maxText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .max) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .max)
        case 3:
            StudioTextField(
                placeholder: "Static (Pin)",
                text: $pinText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .pin) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .pin)
            Picker("Link to", selection: Binding(
                get: { linkTargetID ?? linkCandidates.first?.id },
                set: { linkTargetID = $0 }
            )) {
                ForEach(linkCandidates) { candidate in
                    Text(candidate.name).tag(Optional(candidate.id))
                }
            }
        default:
            StudioTextField(
                placeholder: "Static (Pin)",
                text: $pinText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .pin) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .pin)
        }
    }

    private func advanceFocusedField(from field: Field) {
        let order = fieldOrder
        guard let index = order.firstIndex(of: field) else { return }
        if index + 1 < order.count {
            focusedField = order[index + 1]
        } else {
            focusedField = .name
        }
    }

    private var fieldOrder: [Field] {
        switch statFormat {
        case 2: [.min, .pin, .max, .name]
        default: [.pin, .name]
        }
    }

    private var linkCandidates: [AxisValue] {
        axis.values.filter { $0.statFormat != 3 }
    }

    private func seedDefaults() {
        let suggested = editor.suggestedNewStopValue(for: axis)
        pinText = StudioFormatting.axisValue(suggested)
        minText = StudioFormatting.axisValue(max((axis.min ?? suggested) , suggested - 20))
        maxText = StudioFormatting.axisValue(min((axis.max ?? suggested + 20), suggested + 20))
        if linkTargetID == nil {
            linkTargetID = linkCandidates.first?.id
        }
    }

    private var axisSubtitle: String {
        let title = axis.displayName ?? axis.tag
        if let min = axis.min, let max = axis.max {
            return "\(title) · allowed \(StudioFormatting.axisValue(min)) – \(StudioFormatting.axisValue(max))"
        }
        return title
    }

    private var parsedPin: Double? { Double(pinText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var parsedMin: Double? { Double(minText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var parsedMax: Double? { Double(maxText.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var trimmedName: String {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        if trimmedName.isEmpty { return "Name is required." }
        switch statFormat {
        case 2:
            guard let pin = parsedPin, let min = parsedMin, let max = parsedMax else {
                return "Enter valid min, nominal, and max values."
            }
            return editor.validateAxisStopValue(pin, for: axis)
                ?? (min <= pin && pin <= max ? nil : "Min ≤ Pin ≤ Max required.")
        case 3:
            guard parsedPin != nil else { return "Enter a valid static value." }
            guard linkTargetID != nil else { return "Choose a link target." }
            return parsedPin.flatMap { editor.validateAxisStopValue($0, for: axis) }
        default:
            guard let pin = parsedPin else { return "Enter a valid static value." }
            return editor.validateAxisStopValue(pin, for: axis)
        }
    }

    private var canAdd: Bool { validationMessage == nil }

    private func addStopIfValid() {
        guard canAdd else { return }
        let name = trimmedName
        let tag = axis.tag
        onComplete()
        dismiss()
        Task { @MainActor in
            switch statFormat {
            case 2:
                guard let pin = parsedPin, let min = parsedMin, let max = parsedMax else { return }
                editor.insertAxisStop(axisTag: tag, value: pin, name: name, statFormat: 2, rangeMin: min, rangeMax: max)
            case 3:
                guard let pin = parsedPin else { return }
                editor.insertAxisStop(axisTag: tag, value: pin, name: name, statFormat: 3, linkedStopID: linkTargetID)
            default:
                guard let pin = parsedPin else { return }
                editor.insertAxisStop(axisTag: tag, value: pin, name: name)
            }
        }
    }
}

// MARK: - Fill stops sheet

/// Standalone quick-fill tool, reachable anytime from the axis tree (not gated behind a plan
/// warning). Unlike the resolver's empty-axis fix, this replaces whatever stops already exist,
/// so it doubles as a way to re-fill gaps or redo a fill with a different count/interval —
/// just reopen the sheet and apply again, no undo required.
private struct FillAxisStopsSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let onComplete: () -> Void

    @State private var fillMode: AxisStopFillMode = .evenCount
    @State private var stopCount: Double = 6
    @State private var intervalStep: Double = 1
    @State private var confirmingReplace = false

    private var options: AxisStopFillOptions? {
        AxisStopFillPlanner.options(for: axis)
    }

    private var values: [Double]? {
        switch fillMode {
        case .evenCount:
            return AxisStopFillPlanner.values(for: axis, count: Int(stopCount.rounded()))
        case .fixedInterval:
            return AxisStopFillPlanner.values(for: axis, interval: intervalStep)
        }
    }

    /// Stops whose name doesn't match their bare numeric value have been customized —
    /// replacing without confirmation would silently discard that naming work.
    private var hasCustomNamedStops: Bool {
        axis.values.contains { $0.name != AxisStopSuggestions.formatValue($0.value) }
    }

    private var canApply: Bool {
        (values?.count ?? 0) >= AxisStopFillPlanner.minStopCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sheetSectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fill Stops")
                    .font(StudioTypography.emphasis)
                Text("\(axis.displayName ?? axis.tag) · replaces every stop currently on this axis")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let options {
                AxisStopFillControls(
                    axis: axis,
                    options: options,
                    fillMode: $fillMode,
                    stopCount: $stopCount,
                    intervalStep: $intervalStep
                )
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Fill") {
                    if hasCustomNamedStops {
                        confirmingReplace = true
                    } else {
                        apply()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            guard let options else { return }
            stopCount = Double(options.defaultCount)
            intervalStep = options.defaultInterval
        }
        .alert("Replace Named Stops?", isPresented: $confirmingReplace) {
            Button("Replace", role: .destructive, action: apply)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This axis has stops with custom names. Filling will remove them and replace every stop on this axis.")
        }
    }

    private func apply() {
        guard let values else { return }
        editor.replaceAxisStops(axisTag: axis.tag, values: values)
        onComplete()
        dismiss()
    }
}

// MARK: - Change format sheet

private struct ChangeAxisStopFormatSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let stop: AxisValue
    let onComplete: () -> Void

    @State private var statFormat: Int
    @State private var linkTargetID: String?

    init(axis: AxisDefinition, stop: AxisValue, onComplete: @escaping () -> Void) {
        self.axis = axis
        self.stop = stop
        self.onComplete = onComplete
        _statFormat = State(initialValue: stop.statFormat)
        if stop.statFormat == 3, let linkedValue = stop.linkedValue,
           let target = axis.values.first(where: { $0.id != stop.id && AxisCoordinate.valuesEqual($0.value, linkedValue) }) {
            _linkTargetID = State(initialValue: target.id)
        }
    }

    private var linkCandidates: [AxisValue] {
        axis.values.filter { $0.id != stop.id && $0.statFormat != 3 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Format · \(stop.name)")
                .font(StudioTypography.emphasis)

            Picker("STAT format", selection: $statFormat) {
                Text("Format 1 — static").tag(1)
                Text("Format 2 — range").tag(2)
                Text("Format 3 — linked").tag(3)
            }
            .pickerStyle(.menu)

            if statFormat == 3 {
                Picker("Link to", selection: Binding(
                    get: { linkTargetID ?? linkCandidates.first?.id },
                    set: { linkTargetID = $0 }
                )) {
                    ForEach(linkCandidates) { candidate in
                        Text(candidate.name).tag(Optional(candidate.id))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Apply") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(statFormat == 3 && linkTargetID == nil && linkCandidates.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func apply() {
        editor.updateAxisStopStatFormat(
            axisTag: axis.tag,
            stopID: stop.id,
            format: statFormat,
            linkTargetStopID: statFormat == 3 ? linkTargetID : nil
        )
        onComplete()
        dismiss()
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