import SwiftUI
import VarFontCore

// MARK: - Tokens (Axis Tree is the reference)

enum StudioTypography {
    static let sectionLabel = Font.system(size: 10, weight: .semibold)
    static let columnLabel = Font.system(size: 10, weight: .medium)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11)
    static let meta = Font.system(size: 10)
    static let gridSummaryValue = Font.system(size: 9, weight: .medium)
    static let gridSummaryValueMono = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let tag = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let monoValue = Font.system(size: 11, design: .monospaced)
    static let monoMeta = Font.system(size: 10, design: .monospaced)
    static let emphasis = Font.system(size: 13, weight: .semibold)
}

enum StudioSpacing {
    static let panelHorizontal: CGFloat = 8
    static let panelVertical: CGFloat = 6
    static let rowHorizontal: CGFloat = 6
    static let rowVertical: CGFloat = 2
    static let rowGap: CGFloat = 6
    static let controlGap: CGFloat = 8
    static let sectionGap: CGFloat = 10
    static let listInset: CGFloat = 6
    static let groupHeaderBelow: CGFloat = 3
    static let instanceRowVertical: CGFloat = 3
    static let toolbarVertical: CGFloat = 6
}

enum StudioRadius {
    static let row: CGFloat = 6
    static let chip: CGFloat = 4
    static let control: CGFloat = 5
    static let small: CGFloat = 3
}

enum StudioColors {
    /// Neutral axis/key tags — accent is reserved for selection and interaction.
    static let tagForeground = Color.secondary
    static let tagBackground = Color.secondary.opacity(0.12)
    static let axisValue = Color.orange.opacity(0.85)
    static let selectionFill = Color.accentColor.opacity(0.15)
    static let selectionStroke = Color.accentColor.opacity(0.35)
    static let hoverFill = Color.primary.opacity(0.05)
    static let warningFill = Color.orange.opacity(0.12)
    static let warningFillHover = Color.orange.opacity(0.18)
    static let warningForeground = Color.orange
    /// App-computed totals (grid counts, group sizes) — accent, not axis-value orange.
    static let computedHighlight = Color.accentColor
    /// Drop zone half fills — always visible during drag (top = add, bottom = new).
    static let dropZoneAddFill = Color.accentColor.opacity(0.06)
    static let dropZoneNewFill = Color.green.opacity(0.05)
    /// Drop zone borders when the cursor is over a half.
    static let dropAddExisting = Color.accentColor
    static let dropNewProject = Color.green
}

enum StudioFormatting {
    static func axisValue(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        var text = String(value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    /// Builds `key=value` tokens in naming order for compact list display.
    static func coordPairs(
        coords: [String: Double],
        namingOrder: [String]
    ) -> [String] {
        let extra = coords.keys.filter { !namingOrder.contains($0) }.sorted()
        let tags = namingOrder.filter { coords[$0] != nil } + extra
        return tags.compactMap { tag -> String? in
            guard let value = coords[tag] else { return nil }
            return "\(tag)=\(axisValue(value))"
        }
    }

    /// Truncates at pair boundaries so list rows never cut mid-value (`wght=3…`).
    static func truncatingCoordCaption(pairs: [String], maxLength: Int = 28) -> String {
        var result = ""
        for pair in pairs {
            let candidate = result.isEmpty ? pair : "\(result) \(pair)"
            if candidate.count > maxLength, !result.isEmpty { break }
            if candidate.count > maxLength { return pair }
            result = candidate
        }
        return result
    }
}

// MARK: - Reusable components

struct StudioTagPill: View {
    let text: String
    var compact: Bool = false

    private static let horizontalPadding: CGFloat = 5
    private static let monospacedCharWidth: CGFloat = 5.5

    static func layoutWidth(for text: String) -> CGFloat {
        CGFloat(text.count) * monospacedCharWidth + horizontalPadding * 2
    }

    var body: some View {
        Text(text)
            .font(StudioTypography.tag)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 2)
            .foregroundStyle(StudioColors.tagForeground)
            .background(
                StudioColors.tagBackground,
                in: RoundedRectangle(cornerRadius: compact ? StudioRadius.small : StudioRadius.small)
            )
    }
}

struct StudioSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(StudioTypography.sectionLabel)
            .foregroundStyle(.tertiary)
            .tracking(0.4)
    }
}

struct StudioPanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            StudioSectionLabel(title: title)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 2)
        .frame(height: 32)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct StudioWarningBadge: View {
    let help: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var action: (() -> Void)?

    var body: some View {
        let icon = Image(systemName: systemImage)
            .font(StudioTypography.meta)
            .foregroundStyle(StudioColors.warningForeground)
            .padding(3)
            .background(StudioColors.warningFill, in: RoundedRectangle(cornerRadius: StudioRadius.small))

        if let action {
            Button(action: action) { icon }
                .buttonStyle(.plain)
                .help(help)
        } else {
            icon.help(help)
        }
    }
}

struct StudioFilterChip<Trailing: View>: View {
    var icon: String? = "line.3.horizontal.decrease"
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String? = "line.3.horizontal.decrease",
        label: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Label(label, systemImage: icon)
                    .font(StudioTypography.meta)
            } else {
                Text(label)
                    .font(StudioTypography.meta)
            }
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

struct StudioIncludeCheckbox: View {
    let isOn: Bool
    var isIndeterminate: Bool = false
    let action: () -> Void

    static let size: CGFloat = 13
    static let hitSize: CGFloat = 16

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: StudioRadius.small)
                    .strokeBorder(
                        Color.secondary.opacity(isOn || isIndeterminate ? 0.55 : 0.35),
                        lineWidth: 1
                    )
                    .frame(width: Self.size, height: Self.size)
                if isIndeterminate {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 1.5)
                } else if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.hitSize, height: Self.hitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        if isIndeterminate {
            return "Mixed inclusion — click to include all"
        }
        return isOn ? "Exclude from export" : "Include in export"
    }
}

struct StudioGroupHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: StudioSpacing.rowGap) {
            Text(label)
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(count)")
                .foregroundStyle(StudioColors.computedHighlight)
        }
        .font(StudioTypography.columnLabel)
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StudioSpacing.rowHorizontal)
        .padding(.vertical, 5)
        // Opaque flat band — no padding outside this view; list owns section spacing.
        .background {
            Rectangle()
                .fill(.background)
                .padding(.horizontal, -StudioSpacing.listInset)
        }
    }
}

struct StudioCompactToolbar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.vertical, StudioSpacing.toolbarVertical)
    }
}

struct StudioInspectorBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
            StudioSectionLabel(title: title)
            content
        }
    }
}

struct StudioKeyValueRow: View {
    let key: String
    let value: String
    var valueFont: Font = StudioTypography.body
    var valueColor: Color = .primary
    var muted: Bool = false

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            StudioTagPill(text: key, compact: true)
                .opacity(muted ? 0.65 : 1)
            Text(value)
                .font(valueFont)
                .foregroundStyle(muted ? Color.secondary : valueColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Row chrome

enum StudioRowChrome {
    static func fill(isSelected: Bool, isHovered: Bool, isWarning: Bool) -> Color {
        if isWarning {
            return isHovered ? StudioColors.warningFillHover : StudioColors.warningFill
        }
        if isSelected {
            return StudioColors.selectionFill
        }
        if isHovered {
            return StudioColors.hoverFill
        }
        return .clear
    }
}

struct StudioRowBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var isWarning: Bool = false
    var showsSelectionStroke: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: StudioRadius.row)
            .fill(StudioRowChrome.fill(
                isSelected: isSelected,
                isHovered: isHovered,
                isWarning: isWarning
            ))
            .overlay {
                if isSelected && showsSelectionStroke && !isWarning {
                    RoundedRectangle(cornerRadius: StudioRadius.row)
                        .strokeBorder(StudioColors.selectionStroke, lineWidth: 1)
                }
            }
    }
}

// MARK: - View helpers

extension View {
    func studioPanelPadding() -> some View {
        padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.vertical, StudioSpacing.panelVertical)
    }

    func studioRowInsets() -> some View {
        padding(.horizontal, StudioSpacing.rowHorizontal)
            .padding(.vertical, StudioSpacing.instanceRowVertical)
    }

    func studioCompactControl() -> some View {
        font(StudioTypography.caption)
            .controlSize(.small)
    }
}

// MARK: - Inspector components

struct StudioInspectorConflictBadge: View {
    let count: Int
    var action: (() -> Void)?

    var body: some View {
        let label = Text("\(count) conflict\(count == 1 ? "" : "s")")
            .font(StudioTypography.meta.weight(.medium))
            .foregroundStyle(StudioColors.warningForeground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(StudioColors.warningFill, in: Capsule())

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .help("Show conflict details")
        } else {
            label
        }
    }
}

struct InspectorWarningsDrawer: View {
    let instance: PlannedInstance
    let warnings: [PlanWarning]
    let conflictCount: Int
    @Binding var isExpanded: Bool
    var onShowDuplicates: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                HStack {
                    StudioSectionLabel(title: "Warnings")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, StudioSpacing.panelHorizontal + 2)
                .frame(height: 32)
                .background(.bar)
                .overlay(alignment: .bottom) {
                    Divider()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if instance.duplicate {
                            duplicateCallout
                        }

                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            if warning.code != "duplicate_composed_name" || !instance.duplicate {
                                Label(warning.message, systemImage: "exclamationmark.triangle")
                                    .font(StudioTypography.meta)
                                    .foregroundStyle(StudioColors.warningForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, StudioSpacing.panelHorizontal + 2)
                    .padding(.vertical, StudioSpacing.controlGap)
                }
                .frame(maxHeight: 140)

                Divider()
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: StudioSpacing.controlGap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(StudioTypography.caption)
                        .foregroundStyle(StudioColors.warningForeground)

                    Text("\(conflictCount) conflict\(conflictCount == 1 ? "" : "s")")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, StudioSpacing.panelHorizontal + 2)
                .padding(.vertical, StudioSpacing.toolbarVertical)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(StudioColors.warningFill.opacity(isExpanded ? 0.22 : 0.14))
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var duplicateCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duplicate composed name")
                .font(StudioTypography.bodyMedium)
            Text("Another instance shares this style name.")
                .font(StudioTypography.meta)
                .foregroundStyle(.secondary)
            Button("Show duplicates", action: onShowDuplicates)
                .studioCompactControl()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioColors.warningFill, in: RoundedRectangle(cornerRadius: StudioRadius.row))
    }
}

struct StudioComposedNameCallout: View {
    let name: String
    var isDuplicate: Bool = false

    var body: some View {
        Text(name)
            .font(.system(size: 15, weight: .semibold))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isDuplicate ? StudioColors.warningFill : StudioColors.selectionFill.opacity(0.35),
                in: RoundedRectangle(cornerRadius: StudioRadius.row)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isDuplicate ? StudioColors.warningForeground : Color.accentColor)
                    .frame(width: 3)
            }
    }
}

struct InspectorInstanceNamingChain: View {
    let links: [NamingChainLink]
    var onLinkTap: ((String) -> Void)?

    var body: some View {
        if links.isEmpty {
            Text("No naming chain entries")
                .font(StudioTypography.caption)
                .foregroundStyle(.tertiary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                        if index > 0 {
                            namingArrow
                        }
                        namingSegment(link)
                    }
                }
            }
        }
    }

    private var namingArrow: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 8, height: 1.5)
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.5))
        }
        .padding(.horizontal, 4)
    }

    private func namingSegment(_ link: NamingChainLink) -> some View {
        Button {
            onLinkTap?(link.tag)
        } label: {
            HStack(spacing: 5) {
                StudioTagPill(text: link.tag, compact: true)
                    .opacity(link.elided ? 0.55 : 1)

                Text(link.name)
                    .font(StudioTypography.bodyMedium)
                    .foregroundStyle(link.elided ? .tertiary : .primary)
                    .strikethrough(link.elided, color: Color.secondary.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                link.elided ? Color.secondary.opacity(0.06) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
        }
        .buttonStyle(.plain)
        .disabled(onLinkTap == nil)
        .help(link.elided ? "Elided from composed name" : "Focus this axis stop")
    }
}

struct InspectorAxisCoordinatesView: View {
    let rows: [InspectorAxisCoordRow]
    var selectedStopID: String?
    var onRowTap: ((InspectorAxisCoordRow) -> Void)?
    var onElisionToggle: ((InspectorAxisCoordRow) -> Void)?

    private let badgeWidth: CGFloat = 34
    private let chainWidth: CGFloat = 12
    private let valueWidth: CGFloat = 44
    private let elisionWidth: CGFloat = 52

    private var showsElisionColumn: Bool {
        rows.contains(where: \.showsElisionToggle)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                axisCoordRow(
                    row,
                    isFirst: index == 0,
                    isLast: index == rows.count - 1,
                    linkActiveToNext: chainLinkActive(at: index)
                )
            }
        }
    }

    private func chainLinkActive(at index: Int) -> Bool {
        guard index + 1 < rows.count else { return false }
        return rows[index].participatesInNaming && rows[index + 1].participatesInNaming
    }

    private func axisCoordRow(
        _ row: InspectorAxisCoordRow,
        isFirst: Bool,
        isLast: Bool,
        linkActiveToNext: Bool
    ) -> some View {
        let isSelected = row.stopID == selectedStopID

        return HStack(spacing: StudioSpacing.controlGap) {
            Button {
                onRowTap?(row)
            } label: {
                HStack(spacing: StudioSpacing.controlGap) {
                    chainRail(
                        for: row,
                        isFirst: isFirst,
                        isLast: isLast,
                        linkActiveToNext: linkActiveToNext,
                        isSelected: isSelected
                    )
                    .frame(width: chainWidth)

                    Text(StudioFormatting.axisValue(row.value))
                        .font(StudioTypography.monoValue)
                        .foregroundStyle(StudioColors.axisValue)
                        .opacity(row.participatesInNaming ? 1 : 0.55)
                        .monospacedDigit()
                        .frame(width: valueWidth, alignment: .trailing)

                    StudioTagPill(text: row.tag, compact: true)
                        .opacity(row.participatesInNaming ? 1 : 0.5)
                        .frame(width: badgeWidth, alignment: .center)

                    Text(row.stopName)
                        .font(StudioTypography.body)
                        .foregroundStyle(nameColor(for: row))
                        .strikethrough(row.isElided, color: Color.secondary.opacity(0.45))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background {
                    StudioRowBackground(isSelected: isSelected, isHovered: false)
                }
            }
            .buttonStyle(.plain)
            .disabled(onRowTap == nil || row.stopID == nil)

            if showsElisionColumn {
                Group {
                    if row.showsElisionToggle {
                        Toggle("Elidable", isOn: Binding(
                            get: { row.isElidable },
                            set: { _ in onElisionToggle?(row) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help("Omit this stop from the composed style name when it is the default choice")
                    }
                }
                .frame(width: elisionWidth, alignment: .center)
            }
        }
        .help(row.participatesInNaming
            ? (row.isElided ? "Elided from composed name — focus axis stop" : "Focus this axis stop")
            : "STAT-only axis — not in instance naming")
    }

    private func nameColor(for row: InspectorAxisCoordRow) -> Color {
        if !row.participatesInNaming { return Color.secondary }
        if row.isElided { return Color.secondary.opacity(0.55) }
        return Color.primary
    }

    @ViewBuilder
    private func chainRail(
        for row: InspectorAxisCoordRow,
        isFirst: Bool,
        isLast: Bool,
        linkActiveToNext: Bool,
        isSelected: Bool
    ) -> some View {
        let dotColor: Color = {
            if isSelected { return .accentColor }
            if row.participatesInNaming && !row.isElided { return .accentColor.opacity(0.7) }
            if row.isElided { return .secondary.opacity(0.35) }
            return .secondary.opacity(0.25)
        }()

        VStack(spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
                    .frame(height: 6)
            }

            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            if !isLast {
                Rectangle()
                    .fill(linkActiveToNext ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct InspectorOpenTypeSourcePill: View {
    let source: InspectorOpenTypeSource

    var body: some View {
        Text(source.rawValue)
            .font(StudioTypography.meta)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: StudioRadius.small))
    }
}

struct InspectorOpenTypeTable: View {
    let rows: [InspectorOpenTypeRow]

    private let tableWidth: CGFloat = 52
    private let fieldWidth: CGFloat = 108

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: StudioSpacing.controlGap) {
                Text("Table")
                    .frame(width: tableWidth, alignment: .leading)
                Text("Field")
                    .frame(width: fieldWidth, alignment: .leading)
                Text("Content")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(StudioTypography.columnLabel)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 4)

            ForEach(rows) { row in
                HStack(alignment: .top, spacing: StudioSpacing.controlGap) {
                    Text(row.table)
                        .font(StudioTypography.monoMeta)
                        .frame(width: tableWidth, alignment: .leading)
                    Text(row.field)
                        .font(StudioTypography.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: fieldWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.content)
                            .font(row.isDerived ? StudioTypography.caption : StudioTypography.body)
                            .foregroundStyle(row.isDerived ? .tertiary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !row.sources.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(row.sources, id: \.rawValue) { source in
                                    InspectorOpenTypeSourcePill(source: source)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)

                if row.id != rows.last?.id {
                    Divider()
                }
            }
        }
    }
}
