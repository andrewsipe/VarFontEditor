import SwiftUI
import VarFontCore

struct NamingOrderChainFooter: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("namingChainHideStatOnly") private var hideStatOnly = true
    @State private var isExpanded = true
    @State private var session = NamingChainDragSession()
    /// Stable per-tag chip frames captured in the chain coordinate space.
    @State private var chipFrames: [String: CGRect] = [:]

    private let coordinateSpace = "namingChain"

    private var visibleTags: [String] {
        editor.visibleNamingChainTags(hideStatOnly: hideStatOnly)
    }

    var body: some View {
        Group {
            if let font = editor.selectedFont, !font.axes.isEmpty, !editor.namingChainTags.isEmpty {
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
    }

    private var disclosureContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosureHeader

            if isExpanded {
                VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                    chainTrack

                    exampleRow
                }
                .padding(.top, StudioSpacing.controlGap)
                .padding(.bottom, StudioSpacing.toolbarVertical + 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StudioSpacing.panelHorizontal + 6)
        .padding(.top, StudioSpacing.toolbarVertical + 2)
        .padding(.bottom, isExpanded ? StudioSpacing.toolbarVertical + 2 : StudioSpacing.toolbarVertical)
    }

    private var disclosureHeader: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: StudioSpacing.controlGap) {
                    StudioSquareDisclosureChevron(isExpanded: isExpanded)

                    HStack(spacing: StudioSpacing.controlGap) {
                        HStack(spacing: 4) {
                            Text("Naming order")
                                .font(StudioTypography.caption)
                                .foregroundStyle(.secondary)

                            if editor.projectHasMultipleFiles {
                                Text("· project")
                                    .font(StudioTypography.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .help("Drag a chip to reorder; drop into the outlined gap. Use Hide STAT-only to focus on instance naming axes.")

                        if !isExpanded {
                            Text(editor.namingChainSummary(hideStatOnly: hideStatOnly))
                                .font(StudioTypography.meta)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(height: StudioFieldMetrics.disclosureLabelRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: StudioSpacing.controlGap)

            if isExpanded {
                HStack(spacing: StudioSpacing.controlGap) {
                    hideStatOnlyControl

                    disclosureToolbarDivider

                    restoreButton
                }
            } else {
                Text(editor.namingChainPreviewName)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: StudioFieldMetrics.disclosureLabelRowHeight)
    }

    private var hideStatOnlyControl: some View {
        HStack(spacing: 5) {
            Toggle("Hide STAT-only", isOn: $hideStatOnly)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

            Text("Hide STAT-only")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)
        }
        .help("Show only axes that participate in instance naming. STAT-only and STAT design axes remain editable in the Axis Tree.")
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
        HStack(spacing: StudioSpacing.rowGap) {
            Text("Example")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)

            Text(editor.namingChainPreviewName)
                .font(StudioTypography.bodyMedium)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.tertiary.opacity(0.6), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 2)
                        .padding(.vertical, 2)
                }

            if editor.selectedInstance != nil {
                Text("from selection")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.quaternary)
            }
        }
    }

    // MARK: - Chain track

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
            return "All axes are STAT-only. Turn off Hide STAT-only to reorder, or use Restore to reset axis roles."
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
        if editor.isClarifierNamingToken(tag) {
            return AnyView(clarifierChainChip(tag: tag))
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
                if editor.isClarifierNamingToken(tag) {
                    Text(chainChipLabel(for: tag))
                        .font(StudioTypography.caption)
                        .foregroundStyle(StudioColors.clarifierForeground.opacity(0.5))
                        .lineLimit(1)
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
        if editor.isClarifierNamingToken(tag) {
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

    private func dragGesture(for tag: String) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                if session.draggingTag == nil {
                    session.begin(tag: tag, visibleTags: visibleTags)
                }
                session.ghostPosition = value.location
                session.targetGapIndex = targetGap(at: value.location.x)
            }
            .onEnded { _ in
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
