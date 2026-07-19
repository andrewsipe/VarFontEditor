import SwiftUI
import VarFontCore

struct NamingOrderChainFooter: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("namingChainHideStatOnly") private var hideStatOnly = true
    @State private var isExpanded = true
    @State private var session = NamingChainDragSession()
    @State private var isEditingElidedFallback = false
    @State private var elidedFallbackDraft = ""
    /// Stable per-tag chip frames captured in the chain coordinate space.
    @State private var chipFrames: [String: CGRect] = [:]
    /// Shared expanded-body height so Naming order ↔ Preview don’t jump.
    @State private var footerBodyHeight: CGFloat = 0

    private let coordinateSpace = "namingChain"
    private let footerBodyHeightFallback: CGFloat = 168

    private var visibleTags: [String] {
        editor.visibleNamingChainTags(hideStatOnly: hideStatOnly)
    }

    private var showsFooter: Bool {
        guard let font = editor.selectedFont else { return false }
        return !font.axes.isEmpty || !editor.namingChainTags.isEmpty
    }

    private var isPreviewMode: Bool {
        editor.footerPanelMode == .preview
    }

    var body: some View {
        Group {
            if showsFooter {
                disclosureContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: editor.selectedFontID) {
            session.reset()
        }
        .onChange(of: hideStatOnly) {
            session.reset()
        }
        .onChange(of: visibleTags) {
            // Order changed underneath us (commit, reset, undo); end any stale drag.
            session.reset()
        }
        .onChange(of: editor.footerPanelMode) { _, mode in
            if mode != .preview {
                editor.clearPreviewHover()
            }
        }
    }

    private var disclosureContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureHeader

            if isExpanded {
                Group {
                    switch editor.footerPanelMode {
                    case .namingOrder:
                        namingOrderBody
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: FooterBodyHeightKey.self,
                                        value: geometry.size.height
                                    )
                                }
                            }
                    case .preview:
                        FontPreviewPanel()
                            .frame(
                                maxWidth: .infinity,
                                minHeight: resolvedFooterBodyHeight,
                                maxHeight: resolvedFooterBodyHeight
                            )
                    }
                }
                .padding(.top, StudioSpacing.controlGap)
                .padding(.bottom, StudioSpacing.toolbarVertical + 2)
                .onPreferenceChange(FooterBodyHeightKey.self) { height in
                    guard height > 1 else { return }
                    if abs(footerBodyHeight - height) > 0.5 {
                        footerBodyHeight = height
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isPreviewMode && isExpanded ? 0 : StudioSpacing.panelHorizontal + 6)
        .padding(.top, StudioSpacing.toolbarVertical + 2)
        .padding(.bottom, StudioSpacing.toolbarVertical)
    }

    private var resolvedFooterBodyHeight: CGFloat {
        footerBodyHeight > 1 ? footerBodyHeight : footerBodyHeightFallback
    }

    private var namingOrderBody: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            if editor.namingChainTags.isEmpty {
                Text("No naming axes yet.")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
            } else {
                if editor.projectHasMultipleFiles {
                    Text("Indigo chips are naming axes — each file carries its own stop on that axis.")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                namingOrderTrack

                exampleRow

                elidedFallbackRow
            }
        }
    }

    private var disclosureHeader: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            Button {
                isExpanded.toggle()
            } label: {
                StudioNestedDisclosureChevron(isExpanded: isExpanded)
                    .frame(height: StudioFieldMetrics.disclosureLabelRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse footer" : "Expand footer")

            footerModeSwitcher

            if !isExpanded {
                Text(collapsedSummary)
                    .font(StudioTypography.meta)
                    .foregroundStyle(collapsedSummaryForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: StudioSpacing.controlGap)

            if isExpanded, !isPreviewMode {
                HStack(spacing: StudioSpacing.controlGap) {
                    codeNamingControl

                    disclosureToolbarDivider

                    hideStatOnlyControl

                    disclosureToolbarDivider

                    restoreButton
                }
            } else if !isExpanded {
                Text(collapsedTrailingLabel)
                    .font(StudioTypography.caption)
                    .foregroundStyle(collapsedTrailingForeground)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        }
        .padding(.horizontal, isPreviewMode && isExpanded ? StudioSpacing.panelHorizontal + 6 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: StudioFieldMetrics.disclosureLabelRowHeight)
    }

    private var footerModeSwitcher: some View {
        HStack(spacing: 1) {
            ForEach(StudioFooterPanelMode.allCases) { mode in
                Button {
                    editor.setFooterPanelMode(mode)
                    if !isExpanded {
                        isExpanded = true
                    }
                } label: {
                    Text(mode.title)
                        .font(StudioTypography.meta)
                        .fontWeight(editor.footerPanelMode == mode ? .semibold : .regular)
                        .foregroundStyle(editor.footerPanelMode == mode ? Color.accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: StudioRadius.small)
                                .fill(editor.footerPanelMode == mode ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: StudioRadius.small))
                }
                .buttonStyle(.plain)
                .help(modeHelp(mode))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StudioRadius.control))
    }

    private func modeHelp(_ mode: StudioFooterPanelMode) -> String {
        switch mode {
        case .namingOrder:
            return "Drag chips to reorder naming. Use Hide pinned axes to focus on naming axes."
        case .preview:
            return "Live source-font glyph preview. Hover an instance to peek; click to pin."
        }
    }

    private var collapsedSummary: String {
        if isPreviewMode {
            return editor.previewActiveInstance?.composedName
                ?? "Select an instance"
        }
        return editor.namingChainSummary(hideStatOnly: hideStatOnly)
    }

    private var collapsedSummaryForeground: some ShapeStyle {
        if isPreviewMode && editor.isPreviewHoverPeeking {
            return AnyShapeStyle(Color.accentColor)
        }
        return AnyShapeStyle(.tertiary)
    }

    private var collapsedTrailingLabel: String {
        if isPreviewMode {
            return editor.previewActiveInstance.map { coordsCaption(for: $0) } ?? ""
        }
        return editor.namingChainPreviewName
    }

    private var collapsedTrailingForeground: some ShapeStyle {
        if isPreviewMode {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(
            editor.namingChainPreviewIsElidedFallback
                ? StudioColors.elidedFallbackForeground
                : .primary
        )
    }

    private func coordsCaption(for instance: PlannedInstance) -> String {
        let order = editor.selectedFont?.axes.map(\.tag) ?? Array(instance.coords.keys).sorted()
        return StudioFormatting.coordPairs(coords: instance.coords, namingOrder: order)
            .joined(separator: " · ")
            .replacingOccurrences(of: "=", with: ":")
    }

    private var codeNamingControl: some View {
        HStack(spacing: 5) {
            Toggle(
                "Code",
                isOn: Binding(
                    get: { editor.isCodeNamingEnabled },
                    set: { editor.setCodeNamingEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Text("Code")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
        }
        .help(
            "Include a Code chip in the naming order. When on, Axis Tree and stop sheets show a Code "
                + "column, and composed names include the concatenated stop codes."
        )
    }

    private var hideStatOnlyControl: some View {
        HStack(spacing: 5) {
            Toggle("Hide pinned axes", isOn: $hideStatOnly)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

            Text("Hide pinned axes")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
        }
        .help(
            "Hide axes that do not contribute to composed names (pinned / off-grid). "
                + "Registration axes stay visible because they can appear in names."
        )
    }

    private var disclosureToolbarDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 14)
    }

    private var restoreButton: some View {
        Button("Restore") {
            session.reset()
            editor.restoreNamingDefaults()
        }
        .font(StudioTypography.meta)
        .foregroundStyle(editor.namingDefaultsNeedRestore ? .secondary : .quaternary)
        .buttonStyle(.plain)
        .disabled(!editor.namingDefaultsNeedRestore)
        .help("Restore STAT-inferred naming order and axis instance roles from import")
    }

    private var exampleRow: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
            namingExampleLine(
                label: "Name",
                value: editor.namingChainPreviewName,
                accentValue: editor.namingChainPreviewIsElidedFallback
            )
            namingExampleLine(label: "PostScript", value: editor.namingChainPreviewPostScript)

            if editor.selectedInstance != nil {
                Text("from selection")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func namingExampleLine(
        label: String,
        value: String,
        accentValue: Bool = false
    ) -> some View {
        HStack(spacing: StudioSpacing.rowGap) {
            Text(label)
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
                .frame(width: 68, alignment: .leading)

            Text(value)
                .font(StudioTypography.bodyMedium)
                .fontWeight(label == "PostScript" ? .medium : .semibold)
                .foregroundStyle(accentValue ? StudioColors.elidedFallbackForeground : .primary)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.tertiary.opacity(0.6), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
        }
    }

    private var elidedFallbackRow: some View {
        let display = editor.effectiveElidedFallbackDisplay
        let stored = editor.project?.naming.elidedFallback ?? display.value
        return HStack(spacing: StudioSpacing.rowGap) {
            Text("Elided fallback")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)

            Group {
                if isEditingElidedFallback {
                    StudioTextField(
                        placeholder: "Regular",
                        text: $elidedFallbackDraft,
                        font: StudioTypography.bodyMedium,
                        rowHeight: StudioFieldMetrics.bodyMediumRowHeight,
                        onSubmit: commitElidedFallbackEdit,
                        onCancel: cancelElidedFallbackEdit
                    )
                    .frame(maxWidth: 180)
                } else {
                    Button {
                        elidedFallbackDraft = stored
                        isEditingElidedFallback = true
                    } label: {
                        StudioFieldLabel(
                            text: stored,
                            font: StudioTypography.bodyMedium,
                            rowHeight: StudioFieldMetrics.bodyMediumRowHeight,
                            foreground: StudioColors.elidedFallbackForeground
                        )
                        .frame(maxWidth: 180, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if display.inferred, !isEditingElidedFallback {
                Text("inferred")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.quaternary)
                    .help("No non-elidable baseline segments resolved; using STAT source or Regular.")
            }
        }
        .help("Name shown when all elidable axis segments drop from a composed style.")
        .onChange(of: editor.project?.naming.elidedFallback) { _, value in
            if !isEditingElidedFallback, let value {
                elidedFallbackDraft = value
            }
        }
        .onChange(of: isEditingElidedFallback) { wasEditing, isEditing in
            if wasEditing, !isEditing {
                elidedFallbackDraft = stored
            }
        }
    }

    private func commitElidedFallbackEdit() {
        editor.setElidedFallback(elidedFallbackDraft)
        isEditingElidedFallback = false
    }

    private func cancelElidedFallbackEdit() {
        elidedFallbackDraft = editor.project?.naming.elidedFallback
            ?? editor.effectiveElidedFallbackDisplay.value
        isEditingElidedFallback = false
    }

    // MARK: - Chain track

    /// Fixed PostScript prefix anchor + reorderable naming chain.
    private var namingOrderTrack: some View {
        HStack(alignment: .center, spacing: 0) {
            postScriptPrefixAnchor

            chainLink(isActive: true)
                .padding(.horizontal, 2)

            chainTrack
        }
    }

    private var postScriptPrefixAnchor: some View {
        let prefix = selectedPostScriptPrefix
        let hasPrefix = !prefix.isEmpty

        return Button {
            presentPostScriptPrefixEditing()
        } label: {
            HStack(spacing: 5) {
                Text("PS")
                    .font(StudioTypography.tag)
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))

                Text(hasPrefix ? prefix : "Set prefix…")
                    .font(StudioTypography.caption.weight(hasPrefix ? .semibold : .regular))
                    .foregroundStyle(hasPrefix ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                hasPrefix ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.chip)
                    .strokeBorder(
                        hasPrefix ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: hasPrefix ? [] : [4, 3])
                    )
            }
        }
        .buttonStyle(.plain)
        .help(postScriptPrefixHelp(hasPrefix: hasPrefix))
    }

    private var selectedPostScriptPrefix: String {
        guard let fontID = editor.selectedFontID else { return "" }
        return editor.familyPSPrefix(for: fontID).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func postScriptPrefixHelp(hasPrefix: Bool) -> String {
        if hasPrefix {
            return "PostScript name prefix for this file. Click to edit in Inspector → Project → File naming."
        }
        return "No PostScript prefix set. Click to set it in Inspector → Project → File naming."
    }

    private func presentPostScriptPrefixEditing() {
        editor.focusInspectorProjectScope(fileNaming: .postScriptPrefix)
    }

    private var chainTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if visibleTags.isEmpty {
                    chainEmptyState
                } else {
                    chainContent
                }
            }
            .padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.vertical, StudioSpacing.toolbarVertical)
        }
        .scrollDisabled(session.isDragging)
        .coordinateSpace(name: coordinateSpace)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: StudioRadius.row))
        .overlay {
            RoundedRectangle(cornerRadius: StudioRadius.row)
                .strokeBorder(.quaternary.opacity(0.55), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            ghostOverlay
        }
        .onPreferenceChange(ChainChipFramePreferenceKey.self) { frames in
            // Frames only matter when idle; freezing them during a drag keeps
            // the gesture host stable and avoids a measure -> re-render loop.
            guard !session.isDragging else { return }
            chipFrames = frames
        }
    }

    private var chainEmptyState: some View {
        Text(chainEmptyMessage)
            .font(StudioTypography.meta)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 28)
            .help(chainEmptyMessage)
    }

    private var chainEmptyMessage: String {
        if hideStatOnly, editor.namingChainInstanceTags.isEmpty, !editor.namingChainTags.isEmpty {
            return "Only pinned axes remain. Turn off Hide pinned axes to reorder them, or use Restore to reset axis roles."
        }
        return "No axes in naming order."
    }

    /// Chain is rendered from the stable visible order. Chips never leave the
    /// layout during a drag (that would invalidate the active gesture); instead
    /// the dragged chip dims in place and a placeholder marks the target gap.
    @ViewBuilder
    private var chainContent: some View {
        let tags = visibleTags

        HStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                if showPlaceholder(at: index) {
                    placeholderChip
                    chainLink(isActive: false)
                }

                chainChip(tag: tag)
                    .overlay(chipFrameReader(tag: tag))

                if index < tags.count - 1 {
                    chainLink(isActive: chainLinkActive(after: tag))
                }
            }

            if showPlaceholder(at: tags.count) {
                chainLink(isActive: false)
                placeholderChip
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(.easeOut(duration: 0.12), value: session.targetGapIndex)
    }

    /// Show the placeholder only at gaps that would actually change the order.
    private func showPlaceholder(at gap: Int) -> Bool {
        guard session.isDragging, session.targetGapIndex == gap else { return false }
        let from = session.fromIndex
        return gap != from && gap != from + 1
    }

    private func chipFrameReader(tag: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ChainChipFramePreferenceKey.self,
                value: [tag: proxy.frame(in: .named(coordinateSpace))]
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Chips

    private func chainChip(tag: String) -> some View {
        if editor.isPostscriptHyphenToken(tag) {
            return AnyView(postscriptHyphenChip(tag: tag))
        }
        if editor.isCodeNamingToken(tag) {
            return AnyView(codeChainChip(tag: tag))
        }
        if editor.isClarifierNamingToken(tag) {
            return AnyView(clarifierChainChip(tag: tag))
        }
        if editor.isRegistrationNamingAxis(tag: tag) {
            return AnyView(registrationChainChip(tag: tag))
        }
        let inGrid = editor.axisParticipatesInInstanceGrid(tag: tag)
        let isDragging = session.draggingTag == tag

        return AnyView(
            HStack(spacing: 5) {
                StudioIncludeCheckbox(isOn: inGrid) {
                    editor.setAxisInstanceGridEnabled(tag: tag, enabled: !inGrid)
                }

                chainChipBody(tag: tag, inGrid: inGrid)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                inGrid ? StudioColors.surfaceMuted : Color.clear,
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
            .overlay {
                if !inGrid {
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .opacity(isDragging ? 0.3 : 1)
        )
    }

    private func postscriptHyphenChip(tag: String) -> some View {
        let isDragging = session.draggingTag == tag

        return Text("[-] PS hyphen")
            .font(StudioTypography.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.chip)
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
            }
            .opacity(isDragging ? 0.3 : 1)
            .contentShape(Rectangle())
            .help("Drag to set where the PostScript hyphen splits the style segment (fvar postscriptNameID field).")
            .gesture(dragGesture(for: tag))
    }

    private func codeChainChip(tag: String) -> some View {
        let isDragging = session.draggingTag == tag

        return Text("Code")
            .font(StudioTypography.caption.weight(.semibold))
            .foregroundStyle(StudioColors.codeForeground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(StudioColors.codeBackground, in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.chip)
                    .strokeBorder(StudioColors.codeStroke, lineWidth: 0.5)
            }
            .opacity(isDragging ? 0.3 : 1)
            .contentShape(Rectangle())
            .help("Classification code — concatenated from Axis Tree stop codes in axis order. Drag to reorder.")
            .gesture(dragGesture(for: tag))
    }

    private func clarifierChainChip(tag: String) -> some View {
        let isDragging = session.draggingTag == tag
        let label = editor.clarifierLabels(for: editor.selectedFontID ?? "").first {
            NamingToken.clarifierCategory(for: tag) == $0.category
        }?.label ?? editor.axisDisplayName(for: tag)

        return Text(label)
            .font(StudioTypography.caption)
            .foregroundStyle(StudioColors.clarifierForeground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(StudioColors.clarifierBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.chip)
                    .strokeBorder(StudioColors.clarifierStroke, lineWidth: 0.5)
            }
            .opacity(isDragging ? 0.3 : 1)
            .contentShape(Rectangle())
            .help("Legacy clarifier token — prefer registration axes in the Axis Tree")
            .gesture(dragGesture(for: tag))
    }

    private func registrationChainChip(tag: String) -> some View {
        let isDragging = session.draggingTag == tag

        return HStack(spacing: 5) {
            StudioTagPill(text: tag, compact: true, role: .registration)

            Text(editor.axisDisplayName(for: tag))
                .font(StudioTypography.caption)
                .foregroundStyle(StudioColors.registrationForeground)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            StudioColors.registrationBackground.opacity(0.5),
            in: RoundedRectangle(cornerRadius: StudioRadius.chip)
        )
        .overlay {
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .strokeBorder(StudioColors.registrationStroke, lineWidth: 0.5)
        }
        .opacity(isDragging ? 0.3 : 1)
        .contentShape(Rectangle())
        .gesture(dragGesture(for: tag))
    }

    /// The draggable portion of a chip (tag pill + label). The checkbox is excluded
    /// from the drag hit area so toggling grid membership never starts a drag.
    private func chainChipBody(tag: String, inGrid: Bool) -> some View {
        HStack(spacing: 5) {
            StudioTagPill(text: tag, compact: true)
                .fixedSize()

            Text(editor.axisDisplayName(for: tag))
                .font(StudioTypography.caption)
                .foregroundStyle(inGrid ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .gesture(dragGesture(for: tag))
    }

    private func chainChipLabel(for tag: String) -> String {
        if editor.isClarifierNamingToken(tag),
           let fontID = editor.selectedFontID,
           let label = editor.clarifierLabels(for: fontID).first(where: {
               NamingToken.clarifierCategory(for: tag) == $0.category
           })?.label {
            return label
        }
        return editor.axisDisplayName(for: tag)
    }

    private var placeholderChip: some View {
        Group {
            if let tag = session.draggingTag {
                if editor.isPostscriptHyphenToken(tag) {
                    Text("[-] PS hyphen")
                        .font(StudioTypography.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else if editor.isCodeNamingToken(tag) {
                    Text("Code")
                        .font(StudioTypography.caption.weight(.semibold))
                        .foregroundStyle(StudioColors.codeForeground.opacity(0.5))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else if editor.isClarifierNamingToken(tag) {
                    Text(chainChipLabel(for: tag))
                        .font(StudioTypography.caption)
                        .foregroundStyle(StudioColors.clarifierForeground.opacity(0.5))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                } else if editor.isRegistrationNamingAxis(tag: tag) {
                    HStack(spacing: 5) {
                        StudioTagPill(text: tag, compact: true, role: .registration)
                            .opacity(0.4)

                        Text(chainChipLabel(for: tag))
                            .font(StudioTypography.caption)
                            .foregroundStyle(StudioColors.registrationForeground.opacity(0.5))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                } else {
                    HStack(spacing: 5) {
                        StudioTagPill(text: tag, compact: true)
                            .opacity(0.4)

                        Text(chainChipLabel(for: tag))
                            .font(StudioTypography.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        }
        .transition(.opacity)
    }

    private var ghostOverlay: some View {
        Group {
            if let tag = session.draggingTag {
                ghostChip(for: tag)
                    .overlay {
                        RoundedRectangle(cornerRadius: StudioRadius.chip)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .opacity(0.9)
                    .position(session.ghostPosition)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func ghostChip(for tag: String) -> some View {
        if editor.isPostscriptHyphenToken(tag) {
            Text("[-] PS hyphen")
                .font(StudioTypography.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
        } else if editor.isCodeNamingToken(tag) {
            Text("Code")
                .font(StudioTypography.caption.weight(.semibold))
                .foregroundStyle(StudioColors.codeForeground)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(StudioColors.codeBackground, in: RoundedRectangle(cornerRadius: StudioRadius.chip))
        } else if editor.isClarifierNamingToken(tag) {
            Text(chainChipLabel(for: tag))
                .font(StudioTypography.caption)
                .foregroundStyle(StudioColors.clarifierForeground)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    StudioColors.clarifierBackground.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: StudioRadius.chip)
                )
        } else if editor.isRegistrationNamingAxis(tag: tag) {
            HStack(spacing: 5) {
                StudioTagPill(text: tag, compact: true, role: .registration)

                Text(chainChipLabel(for: tag))
                    .font(StudioTypography.caption)
                    .foregroundStyle(StudioColors.registrationForeground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                StudioColors.registrationBackground.opacity(0.5),
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
        } else {
            HStack(spacing: 5) {
                StudioTagPill(text: tag, compact: true)

                Text(chainChipLabel(for: tag))
                    .font(StudioTypography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                StudioColors.surfaceInset,
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
        }
    }

    // MARK: - Connectors

    private func chainLinkActive(after tag: String) -> Bool {
        let tags = visibleTags
        guard let index = tags.firstIndex(of: tag), index + 1 < tags.count else { return false }
        let next = tags[index + 1]
        return editor.axisParticipatesInInstanceGrid(tag: tag)
            && editor.axisParticipatesInInstanceGrid(tag: next)
    }

    private func chainLink(isActive: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.22))
                .frame(width: 10, height: 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .light))
                .foregroundStyle(isActive ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.45))
        }
        .padding(.horizontal, 1)
    }

    // MARK: - Drag gesture

    private func presentClarifierNaming() {
        editor.focusInspectorProjectScope(fileNaming: .section)
    }

    private func dragGesture(for tag: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                if session.draggingTag == nil {
                    session.begin(tag: tag, visibleTags: visibleTags)
                }
                session.ghostPosition = value.location
                session.targetGapIndex = targetGap(at: value.location.x)
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                if editor.isClarifierNamingToken(tag), session.draggingTag == nil, moved < 4 {
                    presentClarifierNaming()
                    return
                }
                commitOrCancel()
            }
    }

    /// Computes the target gap index (`0...count`) from the pointer X using the
    /// frozen chip frames. Gap N sits before the chip at index N.
    private func targetGap(at x: CGFloat) -> Int? {
        let tags = session.originalVisibleTags
        guard !tags.isEmpty else { return nil }

        for (index, tag) in tags.enumerated() {
            guard let frame = chipFrames[tag] else { continue }
            if x < frame.midX {
                return index
            }
        }
        return tags.count
    }

    private func commitOrCancel() {
        guard let tag = session.draggingTag,
              let gap = session.targetGapIndex else {
            session.reset()
            return
        }

        // Gap is in the original visible-order index space (chips never moved).
        let originalIndex = session.fromIndex
        let landedSameSpot = gap == originalIndex || gap == originalIndex + 1
        if landedSameSpot {
            session.reset()
            return
        }

        let fullInsertBefore = editor.namingChainInsertIndex(
            moving: tag,
            visibleInsertBefore: gap,
            hideStatOnly: hideStatOnly
        )
        let newOrder = EditorViewModel.moveTag(
            editor.namingChainTags,
            moving: tag,
            toIndex: fullInsertBefore
        )
        session.reset()
        editor.setNamingOrder(newOrder)
    }
}

// MARK: - Drag session

private struct NamingChainDragSession {
    /// Tag currently picked up, or nil when idle.
    var draggingTag: String?
    /// Visible order snapshot at pick-up (stable index space for the gesture).
    private(set) var originalVisibleTags: [String] = []
    /// Index of the dragged tag within `originalVisibleTags`.
    private(set) var fromIndex: Int = 0
    /// Target gap in the (unchanged) visible order, `0...count`, or nil.
    var targetGapIndex: Int?
    /// Ghost chip position in chain coordinate space.
    var ghostPosition: CGPoint = .zero

    var isDragging: Bool { draggingTag != nil }

    mutating func begin(tag: String, visibleTags: [String]) {
        draggingTag = tag
        originalVisibleTags = visibleTags
        fromIndex = visibleTags.firstIndex(of: tag) ?? 0
        targetGapIndex = nil
    }

    mutating func reset() {
        draggingTag = nil
        targetGapIndex = nil
        originalVisibleTags = []
        fromIndex = 0
        ghostPosition = .zero
    }
}

// MARK: - Chip frame reporting

private struct ChainChipFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct FooterBodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
