import SwiftUI

// MARK: - Tokens (Axis Tree is the reference)

enum StudioTypography {
    static let sectionLabel = Font.system(size: 10, weight: .semibold)
    static let columnLabel = Font.system(size: 10, weight: .medium)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11)
    static let meta = Font.system(size: 10)
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
    static let toolbarVertical: CGFloat = 6
}

enum StudioRadius {
    static let row: CGFloat = 6
    static let chip: CGFloat = 4
    static let control: CGFloat = 5
    static let small: CGFloat = 3
}

enum StudioColors {
    static let tagForeground = Color.teal
    static let tagBackground = Color.teal.opacity(0.15)
    static let axisValue = Color.orange.opacity(0.85)
    static let selectionFill = Color.accentColor.opacity(0.15)
    static let selectionStroke = Color.accentColor.opacity(0.35)
    static let hoverFill = Color.primary.opacity(0.05)
    static let warningFill = Color.orange.opacity(0.12)
    static let warningFillHover = Color.orange.opacity(0.18)
    /// Highlights filtered counts and summary figures in dense lists.
    static let dataHighlight = Color(red: 0.90, green: 0.58, blue: 0.22)
    static let dropAddExisting = Color.teal
    static let dropNewProject = Color.accentColor
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
                .foregroundStyle(StudioColors.dataHighlight)
        }
        .font(StudioTypography.columnLabel)
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, StudioSpacing.rowHorizontal)
        .padding(.vertical, StudioSpacing.rowVertical + 2)
        .background {
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .fill(.background)
                .padding(.horizontal, -StudioSpacing.listInset)
        }
        .background {
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .fill(.quaternary.opacity(0.5))
                .padding(.horizontal, -StudioSpacing.listInset)
        }
        .padding(.top, StudioSpacing.sectionGap - 4)
        .padding(.bottom, 2)
        .zIndex(1)
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
            .padding(.vertical, StudioSpacing.rowVertical)
    }

    func studioCompactControl() -> some View {
        font(StudioTypography.caption)
            .controlSize(.small)
    }
}
