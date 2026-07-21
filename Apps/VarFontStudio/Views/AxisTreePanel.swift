import AppKit
import SwiftUI
import VarFontCore

struct AxisTreePanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @EnvironmentObject private var layout: EditorLayoutPreferences
    @State private var expandedAxes: Set<String> = []
    @State private var editingStop: (id: String, field: StopEditField)?
    @State private var addStopRequest: AddAxisStopRequest?
    @State private var addRegistrationRequest: AddRegistrationAxisRequest?
    @State private var fillStopsRequest: FillStopsRequest?
    @State private var formatChangeRequest: StopFormatChangeRequest?
    @State private var tabKeyMonitor: TabKeyMonitor?
    @State private var activeTabNavigation: ((Bool) -> Void)?
    @State private var activeTabStopID: String?
    @State private var axisDragSession = AxisTreeAxisDragSession()
    @State private var axisHeaderFrames: [String: CGRect] = [:]
    private let axisReorderCoordinateSpace = "axisTreeAxisReorder"

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

            axisTreeScopeBand
                .frame(height: StudioChromeBand.scope)
                .padding(.horizontal, StudioSpacing.scrollContentHorizontal)

            Divider()

            axisTreeContextBand
                .frame(height: StudioChromeBand.context)
                .padding(.horizontal, StudioSpacing.scrollContentHorizontal)
                .background(StudioColors.surfaceMuted)
                .overlay(alignment: .bottom) { Divider() }

            if editor.selectedFont != nil {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        axesContent(scrollProxy: scrollProxy)
                    }
                    .padding(.leading, StudioSpacing.scrollContentHorizontal)
                    .padding(.trailing, StudioSpacing.scrollContentHorizontal + StudioSpacing.scrollGutter)
                    .padding(.top, StudioSpacing.panelContentTop)
                    .padding(.bottom, StudioSpacing.panelVertical)
                }
                .transaction { $0.animation = nil }
                .onChange(of: editor.inspectorFocus.axisTreeFocusRequest) { _, request in
                    guard let request else { return }
                    scrollToAxisStop(
                        scrollProxy: scrollProxy,
                        axisTag: request.axisTag,
                        stopID: request.stopID
                    )
                }
                .onChange(of: editor.inspectorFocus.focusedAxisTag) { _, tag in
                    if let tag {
                        expandedAxes.insert(tag)
                    }
                }
                .onChange(of: editor.selectedAxisStopID) { _, stopID in
                    guard let stopID, editor.inspectorFocus.axisTreeFocusRequest == nil else { return }
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
        .sheet(item: $addRegistrationRequest) { _ in
            AddFileAxisSheet {
                addRegistrationRequest = nil
            }
            .environmentObject(editor)
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

    /// Band 2 — project · file glance (peer to Instances/Names and Project/Instance tabs).
    private var axisTreeScopeBand: some View {
        HStack(spacing: StudioSpacing.rowGap) {
            if let project = editor.activeOpenProject {
                Text(editor.projectTabLabel(for: project))
                    .font(StudioTypography.rowName)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Text("No project")
                    .font(StudioTypography.rowName)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let font = editor.selectedFont {
                Text("·")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.quaternary)
                Text(editor.fontBasename(for: font))
                    .font(StudioTypography.rowName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: StudioSpacing.controlGap)

            if editor.isSelectedFontMaster, editor.projectHasMultipleFiles {
                Button("Push Axis Tree") {
                    editor.requestPushMasterAxisTree()
                }
                .font(StudioTypography.meta)
                .buttonStyle(.plain)
                .help("Copy master axis stops to all other files in this project")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Band 3 — instance-grid summary (peer to Instances filter / Inspector project title).
    private var axisTreeContextBand: some View {
        Group {
            if let plan = editor.instancePlan, !plan.formula.parts.isEmpty {
                VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
                    studioSummaryRow("Instance grid", value: gridFormulaText(plan))
                    studioSummaryRow("Generated", value: "\(plan.formula.totalGenerated)")
                }
            } else {
                VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
                    studioSummaryRow("Instance grid", value: "—")
                    studioSummaryRow("Generated", value: "—")
                }
                .opacity(0.55)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func studioSummaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(StudioTypography.bodyMedium)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(StudioTypography.emphasis)
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
            .padding(.horizontal, StudioSpace.x2_5)
            .padding(.vertical, StudioSpace.x2)
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
                    if shouldShowAxisDropGap(before: index) {
                        axisReorderDropGap(
                            height: max(axisDragSession.ghostSize.height, 36)
                        )
                        .padding(.vertical, StudioSpacing.rowGap)
                    } else if index > 0 {
                        Divider()
                            .padding(.vertical, StudioSpacing.rowGap)
                            .opacity(axisDragSession.draggingTag == axis.tag ? 0.2 : 1)
                    }
                    axisBlock(axis, axisIndex: index)
                        .id(axis.tag)
                }
                if shouldShowAxisDropGap(before: font.axes.count) {
                    axisReorderDropGap(
                        height: max(axisDragSession.ghostSize.height, 36)
                    )
                    .padding(.top, StudioSpacing.rowGap)
                }

                Button {
                    addRegistrationRequest = AddRegistrationAxisRequest()
                } label: {
                    axisActionButtonLabel(
                        title: "Add Naming Axis",
                        systemImage: "plus",
                        foreground: StudioColors.registrationForeground,
                        stroke: StudioColors.registrationStroke
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, StudioSpacing.sectionGap)
                .help("Add a naming axis for family identity across files (no fvar scale)")

                if !font.compoundStatValues.isEmpty {
                    CombinationStylesSection(compounds: font.compoundStatValues, axes: font.axes)
                        .padding(.top, StudioSpacing.sectionGap)
                }
            }
            .coordinateSpace(name: axisReorderCoordinateSpace)
            .overlay(alignment: .topLeading) {
                axisReorderGhostOverlay
            }
        }
    }

    @ViewBuilder
    private func axisBlock(_ axis: AxisDefinition, axisIndex: Int) -> some View {
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
                onToggleExpansion: { toggleAxisExpansion(for: axis.tag) },
                onResolveConflict: {
                    editor.presentConflictResolver(for: axis.tag)
                },
                onReviewPlanIssue: {
                    editor.presentFirstResolvablePlanIssue(on: axis.tag)
                },
                onUpdateDisplayName: { name in
                    editor.updateAxisDisplayName(tag: axis.tag, name: name)
                }
            )
            .opacity(axisDragSession.draggingTag == axis.tag ? 0.28 : 1)
            .overlay {
                if axisDragSession.draggingTag == axis.tag {
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .strokeBorder(
                            Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(axisReorderPressThenDragGesture(for: axis.tag))
            .help("Click to expand · click and hold to reorder")
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AxisHeaderFramePreferenceKey.self,
                        value: [axis.tag: proxy.frame(in: .named(axisReorderCoordinateSpace))]
                    )
                }
            }
            .onPreferenceChange(AxisHeaderFramePreferenceKey.self) { frames in
                axisHeaderFrames.merge(frames) { _, new in new }
            }

            if isExpanded, axisDragSession.draggingTag != axis.tag {
                axisDetail(axis)
                    .padding(.top, StudioSpacing.tightGap)
                    .padding(.leading, AxisBlockLayout.stopIndentWidth)
            }
        }
    }

    @ViewBuilder
    private var axisReorderGhostOverlay: some View {
        if let tag = axisDragSession.draggingTag,
           let axis = editor.selectedFont?.axes.first(where: { $0.tag == tag }) {
            let width = max(axisDragSession.ghostSize.width, 120)
            AxisTreeAxisHeader(
                axis: axis,
                isExpanded: expandedAxes.contains(tag),
                hasConflict: false,
                axisWarnings: [],
                resolvablePlanWarnings: [],
                fileRegistrationLabel: axis.lane == .registration ? registrationLabel(for: axis) : nil,
                registrationStops: axis.lane == .registration ? axis.values : [],
                selectedRegistrationStopID: registrationStopID(for: axis),
                isInstanceAxis: .constant(axis.role == .instance),
                onToggleExpansion: {}
            )
            .padding(.horizontal, StudioSpacing.rowHorizontal)
            .padding(.vertical, StudioFieldMetrics.tabChipVerticalPadding)
            .frame(width: width, alignment: .leading)
            .background(
                Color.accentColor.opacity(0.16),
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.chip)
                    .strokeBorder(
                        Color.accentColor.opacity(0.75),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                    )
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
            .offset(x: axisDragSession.ghostOrigin.x, y: axisDragSession.ghostOrigin.y)
            .allowsHitTesting(false)
        }
    }

    private func axisReorderDropGap(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: StudioRadius.chip)
            .strokeBorder(
                Color.secondary.opacity(0.45),
                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
            )
            .background(
                Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityLabel("Drop axis here")
    }

    private func shouldShowAxisDropGap(before index: Int) -> Bool {
        guard axisDragSession.showsDropGap,
              let gap = axisDragSession.targetGapIndex else { return false }
        return gap == index
    }

    /// Click-and-hold on the header starts a reorder drag; a short click still expands/collapses
    /// via the header button (suppressed after a drag).
    private func axisReorderPressThenDragGesture(for tag: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(axisReorderCoordinateSpace)
            ))
            .onChanged { value in
                guard let font = editor.selectedFont else { return }
                switch value {
                case .second(true, let drag):
                    guard let drag else { return }
                    if axisDragSession.draggingTag == nil {
                        let headerFrame = axisHeaderFrames[tag] ?? .zero
                        let grabOffset = CGSize(
                            width: drag.startLocation.x - headerFrame.minX,
                            height: drag.startLocation.y - headerFrame.minY
                        )
                        axisDragSession.begin(
                            tag: tag,
                            axisTags: font.axes.map(\.tag),
                            grabOffset: grabOffset,
                            ghostOrigin: CGPoint(x: headerFrame.minX, y: headerFrame.minY),
                            ghostSize: headerFrame.size,
                            headerFrames: axisHeaderFrames
                        )
                    }
                    axisDragSession.updateGhost(at: drag.location)
                    axisDragSession.targetGapIndex = axisReorderTargetGap(at: drag.location.y)
                default:
                    break
                }
            }
            .onEnded { _ in
                commitAxisReorderOrCancel()
            }
    }

    private func toggleAxisExpansion(for tag: String) {
        if axisDragSession.suppressNextExpansionToggle {
            axisDragSession.suppressNextExpansionToggle = false
            return
        }
        toggleExpansion(for: tag)
    }

    private func axisReorderTargetGap(at y: CGFloat) -> Int? {
        let tags = axisDragSession.originalTags
        guard !tags.isEmpty else { return nil }
        let frames = axisDragSession.frozenHeaderFrames
        for (index, tag) in tags.enumerated() {
            guard let frame = frames[tag] else { continue }
            if y < frame.midY {
                return index
            }
        }
        return tags.count
    }

    private func commitAxisReorderOrCancel() {
        defer {
            // Swallow the click that often follows a press-drag, then clear.
            if axisDragSession.suppressNextExpansionToggle {
                DispatchQueue.main.async {
                    axisDragSession.suppressNextExpansionToggle = false
                }
            }
        }
        guard let tag = axisDragSession.draggingTag,
              let gap = axisDragSession.targetGapIndex else {
            if axisDragSession.draggingTag != nil {
                axisDragSession.reset()
                axisDragSession.suppressNextExpansionToggle = true
            }
            return
        }
        let originalIndex = axisDragSession.fromIndex
        let landedSameSpot = gap == originalIndex || gap == originalIndex + 1
        axisDragSession.reset()
        axisDragSession.suppressNextExpansionToggle = true
        guard !landedSameSpot else { return }
        editor.reorderAxisTree(moving: tag, toIndex: gap)
    }

    // MARK: - Axis detail

    /// Same total height as a stop row (`listRowMinHeight` + `instanceRowVertical` top/bottom)
    /// so these dashed action buttons read as part of the same rhythm as the highlighted rows above.
    private func axisActionButtonLabel(
        title: String,
        systemImage: String,
        foreground: Color = .secondary,
        stroke: Color = Color.secondary.opacity(0.5)
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(StudioTypography.caption)
            .foregroundStyle(foreground)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, minHeight: StudioFieldMetrics.listRowMinHeight)
            .padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.vertical, StudioSpacing.instanceRowVertical)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
                    showDefaultMark: true,
                    showRemoveSlot: true,
                    showCode: editor.isCodeNamingEnabled,
                    valueSortAscending: EditorViewModel.axisStopsValueSortAscending(axis.values),
                    onToggleValueSort: {
                        editor.toggleAxisStopsValueSort(axisTag: axis.tag)
                    }
                )
                .padding(.bottom, AxisDetailSpacing.tableHeaderToFirstRowGap)

                ForEach(axis.values) { stop in
                    axisStopRow(axis: axis, stop: stop, showElidable: showElidable)
                        .id(stop.id)
                }
            }

            if axis.role == .instance || axis.isDesignRecordOnly {
                let showFill = axis.role == .instance && AxisStopFillPlanner.supportsFill(axis)
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
            showDefaultMark: true,
            showCode: editor.isCodeNamingEnabled,
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
            onCommitCode: { editor.updateAxisStopCode(axisTag: axis.tag, stopID: stop.id, code: $0) },
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
        if axis.hasFvarScale || axis.isDesignRecordOnly { return .pin }
        if editor.isCodeNamingEnabled { return .code }
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

