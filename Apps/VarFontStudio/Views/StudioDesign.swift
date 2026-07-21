import AppKit
import SwiftUI
import VarFontCore

// MARK: - Tokens (Axis Tree is the reference)

enum StudioTypography {
    static let sectionLabel = Font.system(size: 10, weight: .semibold)
    static let columnLabel = Font.system(size: 10, weight: .medium)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 10)
    static let meta = Font.system(size: 10)
    static let gridSummaryValue = Font.system(size: 9, weight: .medium)
    static let gridSummaryValueMono = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let tag = Font.system(size: 9, weight: .medium, design: .monospaced)
    static let monoValue = Font.system(size: 10, design: .monospaced)
    static let monoMeta = Font.system(size: 10, design: .monospaced)
    static let emphasis = Font.system(size: 13, weight: .semibold)
    /// Project scope title (project inspector header) — one step above `emphasis`.
    static let projectTitle = Font.system(size: 15, weight: .semibold)
    /// Canonical primary identity in list / tab rows (file basename, etc.).
    /// Weight is applied at the call site (semibold when selected, regular otherwise).
    static let rowName = Font.system(size: 12)
    /// Monospaced sibling of `rowName` for identifier cells in rows (e.g. name-table nameID).
    static let rowNameMono = Font.system(size: 12, design: .monospaced)
    /// Save Review summary metric value.
    static let statValue = Font.system(size: 16, weight: .medium)
    /// Diff section pill labels.
    static let pillLabel = Font.system(size: 9, weight: .semibold)
    /// Disclosure / expand chevrons in axis headers and diff sections.
    static let disclosureChevron = Font.system(size: 10, weight: .semibold)
    /// Compact tab / menu chevrons (8pt).
    static let iconGlyph = Font.system(size: 8, weight: .semibold)
    /// Format-3 link chain — lighter/smaller than adjacent caption text.
    static let linkGlyph = Font.system(size: 10, weight: .regular)
}

/// 4pt spacing scale. Prefer `StudioSpacing` semantic aliases at call sites;
/// reach for `StudioSpace` steps only when no semantic token fits.
///
/// Half-steps (`x0_5`, `x1_5`, …) are first-class — they keep existing densities
/// value-preserving while staying on the 4pt lattice. Micro nudges (1pt / 3pt)
/// are intentional exceptions and stay as named literals on `StudioSpacing`.
enum StudioSpace {
    static let unit: CGFloat = 4

    static let x0_5: CGFloat = unit * 0.5  // 2
    static let x1: CGFloat = unit          // 4
    static let x1_5: CGFloat = unit * 1.5  // 6
    static let x2: CGFloat = unit * 2      // 8
    static let x2_5: CGFloat = unit * 2.5  // 10
    static let x3: CGFloat = unit * 3      // 12
    static let x3_5: CGFloat = unit * 3.5  // 14
    static let x4: CGFloat = unit * 4      // 16
    static let x5: CGFloat = unit * 5      // 20
    static let x6: CGFloat = unit * 6      // 24
    static let x7: CGFloat = unit * 7      // 28
    static let x8: CGFloat = unit * 8      // 32
    static let x9: CGFloat = unit * 9      // 36
    /// Large chrome context band (filter / project title / grid summary).
    static let x17: CGFloat = unit * 17    // 68
}

/// Semantic spacing aliases — always preferred over raw numbers or bare `StudioSpace`
/// steps at call sites. Values are expressed in `StudioSpace` so the 4pt lattice
/// stays the single source of truth.
enum StudioSpacing {
    static let panelHorizontal: CGFloat = StudioSpace.x2
    static let panelVertical: CGFloat = StudioSpace.x1_5
    static let rowHorizontal: CGFloat = StudioSpace.x1_5
    static let rowVertical: CGFloat = StudioSpace.x0_5
    static let rowGap: CGFloat = StudioSpace.x1_5
    /// Tight inter-element gap inside chips / compact tool clusters.
    static let tightGap: CGFloat = StudioSpace.x1
    static let controlGap: CGFloat = StudioSpace.x2
    static let sectionGap: CGFloat = StudioSpace.x2_5
    /// Standard sheet outer inset (pickers, conflict resolver, save review chrome).
    static let sheetOuterPadding: CGFloat = StudioSpace.x5
    /// All-around content inset for cards / inner boxes inside sheets and panels
    /// (looser than `panelHorizontal`, tighter than `sheetOuterPadding`).
    static let cardPadding: CGFloat = StudioSpace.x2_5
    /// Root spacing in stacked editor sheets — slightly looser than `sectionGap` for dense multi-section layouts.
    static let sheetSectionSpacing: CGFloat = StudioSpace.x3_5
    static let listInset: CGFloat = StudioSpace.x1_5
    /// Horizontal inset for scrollable panel bodies — matches `StudioPanelHeader` text edges.
    static let scrollContentHorizontal: CGFloat = StudioSpace.x2_5
    /// Density tier: editor chrome (project toolbar, file sub-bar). Tightest horizontal inset.
    static let editorChromeInset: CGFloat = StudioSpace.x3
    /// Density tier: preview / naming-footer chrome — slightly looser than editor chrome.
    static let previewInset: CGFloat = StudioSpace.x3_5
    /// Extra trailing inset so overlay scroll indicators don't cover row chrome (toggles, badges).
    static let scrollGutter: CGFloat = StudioSpace.x2
    /// Trailing inset for scroll content inside a padded card (card inset + scrollbar gutter).
    static let cardScrollTrailing: CGFloat = StudioSpace.x4
    /// Top inset when scroll content sits directly under `StudioPanelHeader` (no filter/toolbar row).
    static let panelContentTop: CGFloat = toolbarVertical
    /// Off-lattice micro (3pt) — optical gap under group headers; do not "snap" to 4.
    static let groupHeaderBelow: CGFloat = 3
    /// Off-lattice micro (3pt) — dense instance-row vertical padding.
    static let instanceRowVertical: CGFloat = 3
    /// Off-lattice micro (1pt) — hairline gap between instance rows.
    static let instanceRowGap: CGFloat = 1
    static let toolbarVertical: CGFloat = StudioSpace.x1_5
}

enum StudioRadius {
    static let row: CGFloat = StudioSpace.x1_5
    static let chip: CGFloat = StudioSpace.x1
    /// Off-lattice (5pt) — control corner; leave alone.
    static let control: CGFloat = 5
    /// Off-lattice (3pt) — compact corner; leave alone.
    static let small: CGFloat = 3
}

/// Fixed control metrics so display ↔ edit transitions do not shift layout.
///
/// ## Stable Chrome style guide
/// - Pair every `StudioTextField` with a `StudioFieldLabel` at the **same** `rowHeight` when toggling display ↔ edit.
/// - Use `StudioFieldMetrics.*RowHeight` — never ad-hoc `.padding(.vertical)` on `TextField` alone.
/// - Return accepts and resigns focus (`.commit`). Use `.advance` only where Return should move to the next field (e.g. Add Stop sheet).
/// - Escape runs optional `onCancel`, then resigns focus.
/// - Forbidden outside this file: `.textFieldStyle(.roundedBorder)`, raw `TextField`, `.padding(.top, 1)` toolbar hacks.
/// - Selection: default `StudioRowSelectionStyle.fillOnly` — no stroke on list rows.
/// - Chips: use `StudioTabChip` for project/file/save-review tabs (fixed padding, stable height).
/// - Typography: `bodyMedium` (12pt) for compact UI rows; `body` (13pt) for axis stop names and inspector prose.
/// - `StudioKeyValueRow` is for simple inspector key/value rows only — not axis coordinate tables.
///
/// ## Shared chrome contract (one semantic → one primitive)
/// - Dismiss / remove: `StudioDismissButton` only. `.outline` (`xmark.circle`) for
///   close/dismiss, `.fill` (`xmark.circle.fill`) for in-row / in-field remove.
///   Never a naked `xmark`; never `minus.circle` to mean "remove".
/// - Overflow: `StudioOverflowMenu` only (`.toolbar` or `.chip` scale). It never
///   renders the system menu chevron.
/// - Selection radio: `StudioElidableRadio` (or a sibling taking `isOn`) for every
///   mutually-exclusive "picked" control. NOTE: an include/exclude control that
///   carries its own meaning (check vs minus) is a *different* control — do not
///   collapse it into a plain radio.
/// - Count: `StudioCountBadge` only. Dirty: `StudioDirtyDot` only (accent color).
///   Master: `StudioMasterStar` only — shares the dirty-dot alignment slot so
///   the pair centers together (never a naked `star.fill` next to the dot).
/// - Link glyph: `StudioLinkGlyph` — keep outside `Menu` labels. Use
///   `StudioFormat3LinkLabel` only for non-Menu Format-3 suffixes. Add affordance label: `StudioAddLabel`.
/// - Icon scale: `StudioChromeScale` — one glyph weight, two hit targets
///   (`.toolbar` 12/24, `.chip` 12/16). Do not hand-size chrome icons.
///
/// ## Spacing scale (4pt lattice)
/// - Base unit: `StudioSpace.unit` (4pt). Steps: `x0_5`…`x8` (incl. half-steps).
/// - Call sites: use a `StudioSpacing.*` semantic alias. Do not write raw
///   `.padding(8)` / `spacing: 10` for structural spacing.
/// - If no semantic alias fits: use a `StudioSpace.xN` step (not a magic number).
/// - Allowed micro exceptions (do not invent new ones): 1pt / 3pt optical nudges
///   already named on `StudioSpacing` (`instanceRowGap`, `groupHeaderBelow`, …).
/// - Column / panel layout enums (`StopTableLayout`, `AxisBlockLayout`, `SaveReviewLayout`,
///   `FillStopPreviewLayout`, `NameTableLayout`, `InspectorAxisCoordLayout`, …) are
///   local track contracts — not part of the spacing lattice. Stop-style tables (Axis Tree,
///   conflict resolver, combination styles) share `StopTableLayout`.
///
/// ## Density tiers (named on purpose — never "normalize" them into one)
/// - editor: `StudioSpacing.editorChromeInset` — tight toolbar / file-bar chrome.
/// - preview: `StudioSpacing.previewInset` — font preview + naming footer chrome.
/// - sheet: `StudioSpacing.sheetOuterPadding` (20) — modal editors / pickers.
/// - review: `SaveReviewLayout` (24) — deliberately roomier Save Review window (on-lattice).
///
/// ## Cross-panel chrome bands (vertical alignment)
/// Three shared horizontal bands across Axis Tree / Instances / Inspector so
/// body content starts on one baseline. Band heights are 4pt-lattice multiples.
/// Body density below the bands stays local (airy axis tables vs tight instance rows).
/// - `StudioChromeBand.header` — panel title bar
/// - `StudioChromeBand.scope` — tabs / Axis Tree project·file glance
/// - `StudioChromeBand.context` — filter / project title / instance-grid summary
enum StudioFieldMetrics {
    static let horizontalPadding: CGFloat = 6
    static let toolbarIconPointSize: CGFloat = 12
    static let toolbarIconHitSize: CGFloat = 24
    /// Compact chrome icons inside chips / dense trailing clusters — same glyph
    /// point size as toolbar (single visual weight) with a tighter hit target.
    static let chipIconPointSize: CGFloat = 12
    static let chipIconHitSize: CGFloat = 16

    /// Single-line row heights matched to `StudioTypography` tiers.
    static let captionRowHeight: CGFloat = 20
    static let bodyMediumRowHeight: CGFloat = 22
    static let bodyRowHeight: CGFloat = 24
    static let monoValueRowHeight: CGFloat = 20

    /// Tab / file chip chrome — selected state must not change outer height.
    static let tabChipHorizontalPadding: CGFloat = 10
    static let tabChipVerticalPadding: CGFloat = 4
    static let tabChipRowHeight: CGFloat = 22

    /// Shared layout slot for adjacent chip status badges (master star, dirty dot).
    static let statusBadgeSlot: CGFloat = 8
    static let dirtyDotSize: CGFloat = 6
    static let masterStarPointSize: CGFloat = 8

    /// DisclosureGroup label rows (file naming, naming order footer).
    static let disclosureLabelRowHeight: CGFloat = 22

    /// Standard selectable list row (instances, inspector coords).
    static let listRowMinHeight: CGFloat = 22

    static func rowHeight(caption: Bool = false, bodyMedium: Bool = false, body: Bool = false, monoValue: Bool = false) -> CGFloat {
        if body { return bodyRowHeight }
        if bodyMedium { return bodyMediumRowHeight }
        if monoValue { return monoValueRowHeight }
        return captionRowHeight
    }
}

/// List / row selection chrome policy.
enum StudioRowSelectionStyle {
    /// Fill highlight only — default for instances, axis stops, inspector rows.
    case fillOnly
    /// Fill plus hairline stroke — avoid; reserved for exceptional keyboard-focus affordance.
    case fillAndStroke
}

enum StudioColors {
    /// Neutral axis/key tags — accent is reserved for selection and interaction.
    static let tagForeground = Color.secondary
    static let tagBackground = Color.secondary.opacity(0.12)
    static let axisValue = Color.orange.opacity(0.85)
    static let selectionFill = Color.accentColor.opacity(0.10)
    static let selectionStroke = Color.accentColor.opacity(0.20)
    static let hoverFill = Color.primary.opacity(0.05)
    static let warningFill = Color.orange.opacity(0.12)
    static let warningFillHover = Color.orange.opacity(0.18)
    static let warningForeground = Color.orange
    static let warningStroke = Color.orange.opacity(0.45)
    static let successStroke = Color.green.opacity(0.45)
    static let successForeground = Color.green
    static let errorForeground = Color.red
    static let errorStroke = Color.red.opacity(0.5)
    /// Save Review diff semantics.
    static let diffRemoved = Color(red: 0.97, green: 0.44, blue: 0.44)
    static let diffAdded = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let diffReflowed = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let diffProtected = Color(red: 0.38, green: 0.65, blue: 0.98)
    /// Neutral panel surfaces.
    static let surfaceSubtle = Color.primary.opacity(0.03)
    static let surfaceMuted = Color.primary.opacity(0.04)
    static let surfaceLight = Color.primary.opacity(0.05)
    static let surfaceInset = Color.primary.opacity(0.06)
    static let surfaceStroke = Color.primary.opacity(0.08)
    static let surfaceStrokeStrong = Color.primary.opacity(0.10)
    /// App-computed totals (grid counts, group sizes) — accent, not axis-value orange.
    static let computedHighlight = Color.accentColor
    /// STAT elided fallback — name when all elidable segments drop (naming footer, instance list).
    static let elidedFallbackForeground = Color.accentColor
    /// Registration / design-record axes — file identity (indigo; absorbed clarifier language).
    static let registrationForeground = Color(red: 0.55, green: 0.45, blue: 0.95)
    static let registrationBackground = Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.14)
    static let registrationStroke = Color(red: 0.55, green: 0.45, blue: 0.95).opacity(0.35)
    /// Legacy clarifier alias — same indigo as registration.
    static let clarifierForeground = registrationForeground
    static let clarifierBackground = registrationBackground
    static let clarifierStroke = registrationStroke
    /// Classification code chip — amber, distinct from registration indigo.
    static let codeForeground = Color(red: 0.78, green: 0.52, blue: 0.18)
    static let codeBackground = Color(red: 0.78, green: 0.52, blue: 0.18).opacity(0.14)
    static let codeStroke = Color(red: 0.78, green: 0.52, blue: 0.18).opacity(0.40)
    /// STAT format badges in the axis tree format grid.
    static let statFormat1 = Color.green
    static let statFormat2 = Color.cyan
    static let statFormat3 = Color.accentColor
    /// Drop zone half fills — 5% tint over the target region during drag.
    static let dropZoneFillOpacity: CGFloat = 0.05
    static let dropZoneAddFill = registrationForeground.opacity(dropZoneFillOpacity)
    static let dropZoneNewFill = Color.green.opacity(dropZoneFillOpacity)
    /// Drop zone borders when the cursor is over a half.
    /// Teal (not accentColor) — accentColor is already the app-wide selection
    /// color, so reusing it here would read as "selected" rather than "drop target."
    static let dropAddExisting = registrationForeground
    static let dropNewProject = Color.green
}

enum StudioFormatting {
    static func axisValue(_ value: Double) -> String {
        AxisCoordinateFormat.format(value)
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

enum NamingVisualRole {
    case instance
    case registration
}

struct StudioTagPill: View {
    let text: String
    var compact: Bool = false
    var role: NamingVisualRole = .instance

    private static let horizontalPadding: CGFloat = 5
    private static let monospacedCharWidth: CGFloat = 5.5

    static func layoutWidth(for text: String) -> CGFloat {
        CGFloat(text.count) * monospacedCharWidth + horizontalPadding * 2
    }

    private var foreground: Color {
        switch role {
        case .instance: StudioColors.tagForeground
        case .registration: StudioColors.registrationForeground
        }
    }

    private var background: Color {
        switch role {
        case .instance: StudioColors.tagBackground
        case .registration: StudioColors.registrationBackground
        }
    }

    var body: some View {
        Text(text)
            .font(StudioTypography.tag)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: compact ? StudioRadius.small : StudioRadius.small)
            )
    }
}

struct StudioStatFormatBadge: View {
    let format: Int
    var action: (() -> Void)?

  private var foreground: Color {
        switch format {
        case 2: StudioColors.statFormat2
        case 3: StudioColors.statFormat3
        default: StudioColors.statFormat1
        }
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    badgeLabel
                }
                .buttonStyle(.plain)
                .help("Change STAT format")
            } else {
                badgeLabel
            }
        }
    }

    private var badgeLabel: some View {
        Text("F\(format)")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(foreground.opacity(format == 2 ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(foreground.opacity(0.35), lineWidth: 0.5)
            }
    }
}

struct StudioClarifierPill: View {
    let label: String
    var showCategory: String? = nil
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let showCategory {
                Text(showCategory)
                    .font(StudioTypography.meta)
                    .foregroundStyle(StudioColors.clarifierForeground.opacity(0.85))
            }
            Text(label)
                .font(compact ? StudioTypography.caption : StudioTypography.bodyMedium)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 4)
        .foregroundStyle(StudioColors.clarifierForeground)
        .background(StudioColors.clarifierBackground, in: Capsule())
        .overlay {
            Capsule().strokeBorder(StudioColors.clarifierStroke, lineWidth: 0.5)
        }
    }
}

// MARK: - Pills & badges

/// Capsule pill with semantic diff colors — Save Review section counts.
enum StudioDiffPillStyle {
    case removed, added, changed, reflowed, unchanged, protected

    var foreground: Color {
        switch self {
        case .removed: StudioColors.diffRemoved
        case .added: StudioColors.diffAdded
        case .changed: StudioColors.warningForeground
        case .reflowed: StudioColors.diffReflowed
        case .unchanged: .secondary
        case .protected: StudioColors.diffProtected
        }
    }

    var background: Color { foreground.opacity(0.12) }
    var border: Color { foreground.opacity(0.22) }
}

struct StudioSemanticPill: View {
    let text: String
    let style: StudioDiffPillStyle

    var body: some View {
        Text(text)
            .font(StudioTypography.pillLabel)
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(style.background, in: Capsule())
            .overlay(Capsule().strokeBorder(style.border, lineWidth: 0.5))
    }
}

struct StudioDiffPillItem: Identifiable {
    let id = UUID()
    let text: String
    let style: StudioDiffPillStyle

    init(_ text: String, style: StudioDiffPillStyle) {
        self.text = text
        self.style = style
    }
}

/// Numeric count capsule for aligned metric slots (axis header stop counts).
///
/// **Fixed width:** When `fixedWidth` is set, digits scale down before truncating so trailing
/// header clusters stay aligned. The axis-tree slot is 32pt (fits 1–3 digit counts at `meta`).
/// Use 36pt+ for 4-digit totals. Trailing cluster today: optional Resolve button, count badge,
/// instance-axis toggle — not the legacy "Pinned" label (replaced by the switch).
struct StudioCountBadge: View {
    let text: String
    var highlighted: Bool = true
    var fixedWidth: CGFloat? = nil
    var help: String = ""

    var body: some View {
        Text(text)
            .font(StudioTypography.meta.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(highlighted ? AnyShapeStyle(StudioColors.computedHighlight) : AnyShapeStyle(.secondary))
            .frame(width: fixedWidth)
            // Free (non-aligned) badges need breathing room; fixed-width column
            // badges (axis headers) keep their exact alignment slot.
            .padding(.horizontal, fixedWidth == nil ? 6 : 0)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(highlighted ? 1 : 0.6), in: Capsule())
            .help(help)
    }
}

// MARK: - Disclosure & metrics

/// Icon-swap chevron for custom expand toggles — preserves Save Review / axis header behavior (not `DisclosureGroup` rotation).
struct StudioDisclosureChevron: View {
    var isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(StudioTypography.disclosureChevron)
            .foregroundStyle(.tertiary)
            .frame(width: 12)
    }
}

/// Nested-section chevron (footer rows, combination styles) — larger hit target than top-level disclosure.
struct StudioNestedDisclosureChevron: View {
    var isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down.square" : "chevron.right.square")
            .font(.system(size: StudioFieldMetrics.toolbarIconPointSize))
            .foregroundStyle(.tertiary)
            .frame(width: StudioFieldMetrics.toolbarIconHitSize, height: StudioFieldMetrics.toolbarIconHitSize)
    }
}

@available(*, deprecated, renamed: "StudioNestedDisclosureChevron")
typealias StudioSquareDisclosureChevron = StudioNestedDisclosureChevron

/// Mutually exclusive elision control for axis stops (one elidable stop per axis).
/// Use `StudioElidableSwitch` only where each row can elide independently (e.g. combination styles).
struct StudioElidableRadio: View {
    let isOn: Bool
    var helpText: String? = nil
    let action: () -> Void

    private var resolvedHelp: String {
        helpText
            ?? (isOn
                ? "Clear elidable stop — only one stop per axis can be elided"
                : "Mark as the elidable stop for this axis (clears any other)")
    }

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded { action() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elidable")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityAction { action() }
        .help(resolvedHelp)
    }
}

/// Independent on/off elision for rows that are not mutually exclusive (combination styles).
struct StudioElidableSwitch: View {
    @Binding var isOn: Bool
    var helpText: String = "Omit this name from the composed style when it is the default choice"

    var body: some View {
        Toggle("Elidable", isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(helpText)
    }

    init(isOn: Binding<Bool>, helpText: String = "Omit this name from the composed style when it is the default choice") {
        _isOn = isOn
        self.helpText = helpText
    }

    init(isOn: Bool, helpText: String = "Omit this name from the composed style when it is the default choice", action: @escaping () -> Void) {
        _isOn = Binding(get: { isOn }, set: { _ in action() })
        self.helpText = helpText
    }
}

/// Save Review / dashboard summary metric tile.
///
/// **Sizing contract** (`minWidth` defaults to 72):
/// - **Values:** `statValue` (16pt) with `monospacedDigit()` — comfortable through 4 digits at 72pt;
///   5+ digits may need a wider `minWidth` (84–96) rather than shrinking the value line.
/// - **Labels:** `gridSummaryValue` (9pt uppercase, +0.4 tracking), single line — fits labels up to
///   ~14 characters at 72pt (`"New name IDs"`, `"STAT values"`). Longer copy should use a shorter
///   label, raise `minWidth`, or accept `minimumScaleFactor` shrink — labels do not wrap.
struct StudioMetricCard: View {
    let value: String
    let label: String
    var minWidth: CGFloat = 72
    var accentValue: Bool = false
    /// When true, the visible card (background + border included) stretches to
    /// fill its column instead of hugging its content and floating in extra
    /// invisible frame space — use for equal-width metric rows (Save Review cards).
    var fillsWidth: Bool = false
    /// Save Review summary row — prototype `.card .n` scale (20pt bold value).
    var prominent: Bool = false

    var body: some View {
        VStack(spacing: prominent ? 3 : 2) {
            Text(value)
                .font(prominent ? .system(size: 20, weight: .bold) : StudioTypography.statValue)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(accentValue ? StudioColors.computedHighlight : .primary)
            Text(label)
                .font(prominent ? .system(size: 10, weight: .medium) : StudioTypography.gridSummaryValue)
                .textCase(.uppercase)
                .tracking(prominent ? 0.35 : 0.4)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(minWidth: minWidth, maxWidth: fillsWidth ? .infinity : nil)
        .padding(.horizontal, prominent ? 6 : 12)
        .padding(.vertical, prominent ? 10 : 8)
        .background(StudioColors.surfaceLight, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(StudioColors.surfaceStrokeStrong, lineWidth: 0.5)
        )
    }
}

// MARK: - Diff rows

enum StudioDiffRowSide {
    case before
    case after
}

/// TTX side-by-side diff row — annotation bar, key, value, optional role label.
struct StudioDiffRow: View {
    let change: CommitDiffChangeKind
    let key: String
    let value: String?
    var roleLabel: String? = nil
    let side: StudioDiffRowSide
    var reflow: Bool = false
    var protected: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Self.annotationColor(change: change, side: side, reflow: reflow, protected: protected))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let value, !value.isEmpty {
                    HStack(spacing: 6) {
                        Text(value)
                            .font(StudioTypography.monoMeta)
                            .foregroundStyle(Self.valueColor(change: change, side: side, reflow: reflow, protected: protected))
                            .lineLimit(1)
                        if let roleLabel, !roleLabel.isEmpty {
                            Text(roleLabel)
                                .font(StudioTypography.meta)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(StudioColors.surfaceInset, in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("—")
                        .font(StudioTypography.monoMeta)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    static func annotationColor(
        change: CommitDiffChangeKind,
        side: StudioDiffRowSide,
        reflow: Bool = false,
        protected: Bool = false
    ) -> Color {
        if protected { return StudioColors.diffProtected }
        if reflow { return StudioColors.diffReflowed }
        switch change {
        case .added:
            return side == .after ? StudioColors.diffAdded : .clear
        case .removed:
            return side == .before ? StudioColors.diffRemoved : .clear
        case .changed:
            return StudioColors.warningForeground
        case .unchanged:
            return .clear
        }
    }

    static func valueColor(
        change: CommitDiffChangeKind,
        side: StudioDiffRowSide,
        reflow: Bool = false,
        protected: Bool = false
    ) -> Color {
        if protected { return StudioColors.diffProtected }
        if reflow { return StudioColors.diffReflowed }
        switch change {
        case .added:
            return side == .after ? StudioColors.diffAdded : .primary
        case .removed:
            return side == .before ? StudioColors.diffRemoved : .primary
        case .changed:
            return StudioColors.warningForeground
        case .unchanged:
            return .primary
        }
    }
}

// MARK: - Save Review (streamlined diff)

/// Spacing tokens for the Save Review window — roomier density tier, on the 4pt lattice.
/// (`gutterWidth` stays a 3pt micro for the change rail.)
enum SaveReviewLayout {
    static let horizontalPadding: CGFloat = StudioSpace.x6 // 24
    static let summaryCardGap: CGFloat = StudioSpace.x2 // 8
    static let chromeSectionGap: CGFloat = StudioSpace.x3 // 12
    static let filterBadgeGap: CGFloat = StudioSpace.x1_5 // 6
    /// nameID slot column (right-aligned digits) — sits between field label and value.
    static let nameIDColumnWidth: CGFloat = 36
    /// Gap between field-label column and nameID.
    static let nameIDColumnLeadingGap: CGFloat = StudioSpace.x2 // 8
    /// Gap between nameID and value column.
    static let nameIDColumnTrailingGap: CGFloat = StudioSpace.x2 // 8
    /// Field label column — human row identifier (+ optional detail line).
    static let fieldColumnWidth: CGFloat = 200
    static let rowVerticalPadding: CGFloat = StudioSpace.x2 // 8
    /// Search row + tab headline band (shared so those toolbars stay the same height).
    static let toolRowMinHeight: CGFloat = StudioSpace.x9 // 36
    static let toolRowVerticalPadding: CGFloat = StudioSpace.x1_5 // 6
    static let gutterWidth: CGFloat = 3
    static let gutterLeadingPadding: CGFloat = StudioSpace.x6 // 24
    static let gutterTrailingPadding: CGFloat = StudioSpace.x3 // 12

    /// Prototype `--bg` / row canvas — opaque so sticky headers don't show scroll-through.
    static let canvasBackground = Color(red: 0.11, green: 0.11, blue: 0.118)
    /// Prototype `.phase` band — opaque sticky header fill.
    static let phaseHeaderBackground = Color(red: 0.133, green: 0.133, blue: 0.141)
}

extension SaveReviewDisplayCategory {
    var pillStyle: StudioDiffPillStyle {
        switch self {
        case .same: .unchanged
        case .protected: .protected
        case .reflow: .reflowed
        case .renamed: .changed
        case .added: .added
        case .removed: .removed
        }
    }
}

struct StudioFilterBadge: View {
    let category: SaveReviewDisplayCategory
    let count: Int
    var isHidden: Bool
    var isIsolated: Bool
    let action: (_ commandClick: Bool) -> Void

    var body: some View {
        Button {
            action(NSEvent.modifierFlags.contains(.command))
        } label: {
            Text("\(category.filterLabel.uppercased()) \(count)")
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(isHidden ? AnyShapeStyle(.tertiary) : AnyShapeStyle(category.pillStyle.foreground))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    isHidden ? Color.clear : category.pillStyle.background,
                    in: RoundedRectangle(cornerRadius: 3)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            isIsolated ? Color.primary.opacity(0.22) : (isHidden ? Color.clear : category.pillStyle.border),
                            lineWidth: isIsolated ? 1 : 0.5
                        )
                }
                .opacity(isHidden ? 0.32 : 1)
        }
        .buttonStyle(.plain)
    }
}

struct StudioSaveReviewTabBar: View {
    let tabs: [SaveReviewTabPresentation]
    @Binding var selectedTab: SaveReviewTableTab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tabs, id: \.tabID) { tab in
                let isSelected = selectedTab == tab.id
                let hasChanges = tab.changedCount > 0
                Button {
                    selectedTab = tab.id
                } label: {
                    HStack(spacing: 7) {
                        Text(tab.label)
                            .font(StudioTypography.bodyMedium.weight(isSelected ? .semibold : .regular))
                        Text("\(tab.changedCount) of \(tab.totalCount)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(hasChanges ? StudioColors.warningForeground : Color.secondary.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background(
                        isSelected ? StudioColors.surfaceLight : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .shadow(color: isSelected ? Color.black.opacity(0.2) : .clear, radius: 2, y: 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(StudioColors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(StudioColors.surfaceStrokeStrong, lineWidth: 0.5)
        )
    }
}

struct StudioSaveReviewPhaseHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SaveReviewLayout.horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(SaveReviewLayout.phaseHeaderBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(StudioColors.surfaceStroke)
                    .frame(height: 0.5)
            }
            .zIndex(1)
    }
}

struct StudioSaveReviewCategoryTag: View {
    let category: SaveReviewDisplayCategory

    var body: some View {
        Text(category.filterLabel.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.3)
            .foregroundStyle(category.pillStyle.foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(category.pillStyle.background, in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Save Review row typography
//
// File-bound content (coordinates, quoted strings, tag=value, nameID slots in values)
// → monospaced. Human labels, section context, and read-only notes → system sans.
enum SaveReviewTypography {
    static let fieldLabel = Font.system(size: 12, weight: .medium)
    static let fieldLabelMono = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let fieldDetail = Font.system(size: 10)
    static let nameID = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let value = Font.system(size: 10.5, design: .monospaced)
    static let valueSecondary = Font.system(size: 10, design: .monospaced)
    static let note = Font.system(size: 10)

    /// Row identifier when it is a file-native key (e.g. `wgth = 400`).
    static func fieldTitleFont(_ title: String) -> Font {
        if title.range(of: #"^[a-zA-Z]{4} = "#, options: .regularExpression) != nil {
            return fieldLabelMono
        }
        return fieldLabel
    }

    /// Subtitle lines that carry coordinates / tags use mono; descriptive labels use sans.
    static func fieldDetailFont(_ subtitle: String) -> Font {
        if subtitle.contains("=") || subtitle.hasPrefix("tag=") {
            return valueSecondary
        }
        return fieldDetail
    }
}

struct StudioStreamlinedDiffRow: View {
    let row: SaveReviewRowPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(gutterColor)
                .frame(width: SaveReviewLayout.gutterWidth)
                .padding(.leading, SaveReviewLayout.gutterLeadingPadding)
                .padding(.trailing, SaveReviewLayout.gutterTrailingPadding)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.fieldTitle)
                        .font(SaveReviewTypography.fieldTitleFont(row.fieldTitle))
                        .lineLimit(2)
                    if !row.fieldSubtitle.isEmpty {
                        Text(row.fieldSubtitle)
                            .font(SaveReviewTypography.fieldDetailFont(row.fieldSubtitle))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .frame(width: SaveReviewLayout.fieldColumnWidth, alignment: .leading)
                .layoutPriority(1)

                Group {
                    if let nameID = row.nameID {
                        Text("\(nameID)")
                            .font(SaveReviewTypography.nameID)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    } else {
                        Text("—")
                            .font(SaveReviewTypography.fieldDetail)
                            .foregroundStyle(.quaternary)
                    }
                }
                .frame(width: SaveReviewLayout.nameIDColumnWidth, alignment: .trailing)
                .padding(.leading, SaveReviewLayout.nameIDColumnLeadingGap)
                .padding(.trailing, SaveReviewLayout.nameIDColumnTrailingGap)
                .layoutPriority(2)

                VStack(alignment: .leading, spacing: 3) {
                    if let afterValue = row.afterValue, !afterValue.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            StudioSaveReviewCategoryTag(category: row.category)
                            Text(afterValue)
                                .font(SaveReviewTypography.value)
                                .foregroundStyle(valueColor)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if row.category == .removed {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            StudioSaveReviewCategoryTag(category: row.category)
                            Text("—")
                                .font(SaveReviewTypography.value)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let secondaryLine {
                        Text(secondaryLine)
                            .font(row.noteLine != nil && row.wasLine == nil ? SaveReviewTypography.note : SaveReviewTypography.valueSecondary)
                            .foregroundStyle(.tertiary)
                            .italic(row.noteLine != nil && row.wasLine == nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, SaveReviewLayout.rowVerticalPadding)
        .padding(.trailing, SaveReviewLayout.horizontalPadding)
        .background(SaveReviewLayout.canvasBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StudioColors.surfaceStroke)
                .frame(height: 0.5)
                .padding(.leading, SaveReviewLayout.horizontalPadding)
        }
    }

    /// Collapses `wasLine` + `noteLine` onto a single row so the value column
    /// never grows past badge/value + one secondary line (2 lines total).
    private var secondaryLine: String? {
        let parts = [row.wasLine, row.noteLine].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var gutterColor: Color {
        if row.category == .same {
            return Color.primary.opacity(0.12)
        }
        return row.category.pillStyle.foreground
    }

    private var valueColor: Color {
        switch row.category {
        case .same: .secondary
        case .protected: StudioColors.diffProtected
        default: row.category.pillStyle.foreground
        }
    }
}

struct StudioSectionLabel: View {
    let title: String
    /// When `false` (floating menus/popovers), uses `.secondary` for readable contrast on material surfaces.
    var muted: Bool = true

    var body: some View {
        Text(title.uppercased())
            .font(StudioTypography.sectionLabel)
            .foregroundStyle(muted ? .tertiary : .secondary)
            .tracking(0.4)
    }
}

/// Cross-panel vertical chrome bands — fixed heights so Axis Tree / Instances /
/// Inspector body content shares a start baseline. Values are `StudioSpace` multiples.
enum StudioChromeBand {
    /// Panel title bar (AXIS TREE / INSTANCES / INSPECTOR).
    static let header: CGFloat = StudioSpace.x9
    /// Scope / tab row (Instances|Names, Project|Instance, Axis Tree glance).
    static let scope: CGFloat = StudioSpace.x9
    /// Context / tools row (filter, project title, instance-grid summary).
    static let context: CGFloat = StudioSpace.x17
}

/// Shared panel header band with bottom divider — use for section headers and collapsed panel rails.
struct StudioPanelHeaderChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(height: StudioChromeBand.header)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }
    }
}

/// Panel section header — fixed height via `StudioChromeBand.header`.
struct StudioPanelHeader<Trailing: View>: View {
    let title: String
    var horizontalPadding: CGFloat = StudioSpacing.panelHorizontal + 2
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        horizontalPadding: CGFloat = StudioSpacing.panelHorizontal + 2,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.horizontalPadding = horizontalPadding
        self.trailing = trailing
    }

    var body: some View {
        StudioPanelHeaderChrome {
            HStack(spacing: StudioSpacing.controlGap) {
                StudioSectionLabel(title: title)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, horizontalPadding)
        }
    }
}

struct StudioWarningBadge: View {
    static let slotSize: CGFloat = 16

    let help: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var action: (() -> Void)?

    var body: some View {
        let icon = Image(systemName: systemImage)
            .font(.system(size: 9))
            .foregroundStyle(StudioColors.warningForeground)
            .frame(width: Self.slotSize, height: Self.slotSize)

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

/// Return / Escape keyboard contract for `StudioTextField` and `StudioInlineTextField`.
enum StudioTextSubmitBehavior {
    /// Return accepts the edit and resigns focus — default for forms and inspector fields.
    case commit
    /// Return runs `onSubmit` without resigning — multi-field sheets (Add Stop) that sequence fields on Return.
    case advance
}

@MainActor
enum StudioFieldFocus {
    static func resignIfEditing() {
        guard NSApp.keyWindow?.firstResponder is NSTextView else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

/// Compact text field — fixed row height, dark editable surface, subtle border, no accent focus ring.
struct StudioTextField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = StudioTypography.caption
    var rowHeight: CGFloat = StudioFieldMetrics.captionRowHeight
    /// When false, renders without field chrome (for embedding in `StudioSearchField`).
    var showsFieldChrome: Bool = true

    /// When set, non-empty value text uses this color (e.g. clarifier fields in file naming).
    var filledForeground: Color? = nil
    var onSubmit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var submitBehavior: StudioTextSubmitBehavior = .commit
    var focusBinding: FocusState<Bool>.Binding? = nil

    @FocusState private var internalFocus: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var activeFocus: FocusState<Bool>.Binding {
        focusBinding ?? $internalFocus
    }

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder)
                .font(font)
                .foregroundStyle(.tertiary)
        )
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(valueForeground)
            .padding(.horizontal, showsFieldChrome ? StudioFieldMetrics.horizontalPadding : 0)
            .frame(height: rowHeight, alignment: .center)
            .background {
                if showsFieldChrome {
                    RoundedRectangle(cornerRadius: StudioRadius.control)
                        .fill(fieldBackground)
                }
            }
            .overlay {
                if showsFieldChrome {
                    RoundedRectangle(cornerRadius: StudioRadius.control)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                }
            }
            .focused(activeFocus)
            .modifier(StudioFocusRingSuppression())
            .onSubmit { handleSubmit() }
            .onExitCommand { handleCancel() }
    }

    private func handleSubmit() {
        onSubmit?()
        guard submitBehavior == .commit else { return }
        activeFocus.wrappedValue = false
        StudioFieldFocus.resignIfEditing()
    }

    private func handleCancel() {
        onCancel?()
        activeFocus.wrappedValue = false
        StudioFieldFocus.resignIfEditing()
    }

    private var valueForeground: Color {
        if !isEnabled { return .secondary }
        if !text.isEmpty, let filledForeground { return filledForeground }
        return .primary
    }

    private var fieldBackground: Color {
        activeFocus.wrappedValue ? Color(nsColor: .textBackgroundColor) : Color.primary.opacity(0.05)
    }

    private var borderColor: Color {
        activeFocus.wrappedValue ? Color.primary.opacity(0.22) : Color.secondary.opacity(0.28)
    }
}

/// Search bar with magnifier and optional clear button.
struct StudioSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var isFocused: FocusState<Bool>.Binding? = nil

    @FocusState private var internalFocus: Bool

    private var activeFocus: FocusState<Bool>.Binding {
        isFocused ?? $internalFocus
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)

            StudioTextField(
                placeholder: placeholder,
                text: $text,
                showsFieldChrome: false,
                focusBinding: activeFocus
            )

            if !text.isEmpty {
                StudioDismissButton(scale: .chip, style: .fill, foreground: .tertiary) {
                    text = ""
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(height: StudioFieldMetrics.captionRowHeight + 8)
        .background(
            .quaternary.opacity(0.55),
            in: RoundedRectangle(cornerRadius: StudioRadius.chip)
        )
    }
}

/// Inline table / axis-tree edit field with shared chrome.
struct StudioInlineTextField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = StudioTypography.body
    var foreground: Color = .primary
    var rowHeight: CGFloat = StudioFieldMetrics.bodyRowHeight
    var alignment: TextAlignment = .leading
    var onSubmit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var submitBehavior: StudioTextSubmitBehavior = .commit

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(foreground)
            .multilineTextAlignment(alignment)
            .studioInlineEditField(isActive: true, rowHeight: rowHeight)
            .modifier(StudioFocusRingSuppression())
            .focused($isFocused)
            .onSubmit { handleSubmit() }
            .onExitCommand { handleCancel() }
    }

    private func handleSubmit() {
        onSubmit?()
        guard submitBehavior == .commit else { return }
        isFocused = false
        StudioFieldFocus.resignIfEditing()
    }

    private func handleCancel() {
        onCancel?()
        isFocused = false
        StudioFieldFocus.resignIfEditing()
    }
}

enum StudioTabChipShape {
    case capsule
    case roundedRect
}

/// Project / file / save-review tab chip — stable padding and height.
struct StudioTabChip<Label: View, Trailing: View>: View {
    var isSelected: Bool = false
    var isHighlighted: Bool = false
    var isDropTarget: Bool = false
    var dropTargetTint: Color = StudioColors.dropAddExisting
    var shape: StudioTabChipShape = .capsule
    @ViewBuilder var label: () -> Label
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 5) {
            label()
            trailing()
        }
        .padding(.horizontal, StudioFieldMetrics.tabChipHorizontalPadding)
        .padding(.vertical, StudioFieldMetrics.tabChipVerticalPadding)
        .frame(minHeight: StudioFieldMetrics.tabChipRowHeight)
        .background {
            switch shape {
            case .capsule:
                Capsule()
                    .fill(chipFill)
                    .overlay {
                        if isHighlighted {
                            Capsule()
                                .strokeBorder(StudioColors.selectionStroke, lineWidth: 0.5)
                        }
                    }
            case .roundedRect:
                RoundedRectangle(cornerRadius: StudioRadius.chip)
                    .fill(chipFill)
                    .overlay {
                        if isHighlighted {
                            RoundedRectangle(cornerRadius: StudioRadius.chip)
                                .strokeBorder(StudioColors.selectionStroke, lineWidth: 0.5)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if isDropTarget {
                Rectangle()
                    .fill(dropTargetTint)
                    .frame(height: 1)
                    .padding(.horizontal, shape == .capsule ? 8 : 2)
            }
        }
        .background {
            if isDropTarget {
                chipDropFill
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
    }

    @ViewBuilder
    private var chipDropFill: some View {
        switch shape {
        case .capsule:
            Capsule()
                .fill(dropTargetTint.opacity(StudioColors.dropZoneFillOpacity))
        case .roundedRect:
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .fill(dropTargetTint.opacity(StudioColors.dropZoneFillOpacity))
        }
    }

    private var chipFill: Color {
        if isSelected || isHighlighted {
            return StudioColors.selectionFill
        }
        return Color.primary.opacity(0.04)
    }
}

/// Fixed-height row for `DisclosureGroup` labels — prevents expand/collapse layout shift.
struct StudioDisclosureLabelRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: StudioFieldMetrics.disclosureLabelRowHeight, alignment: .center)
    }
}

/// Static label occupying the same vertical space as `StudioTextField` at a given tier.
struct StudioFieldLabel: View {
    let text: String
    var font: Font = StudioTypography.caption
    var rowHeight: CGFloat = StudioFieldMetrics.captionRowHeight
    var fontWeight: Font.Weight = .regular
    var foreground: Color = .primary

    var body: some View {
        Text(text)
            .font(font.weight(fontWeight))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, StudioFieldMetrics.horizontalPadding)
            .frame(height: rowHeight, alignment: .leading)
    }
}

/// Chrome icon scale — one glyph weight, two hit targets. Chrome icons should be
/// sized through this, never hand-tuned per call site.
enum StudioChromeScale {
    case toolbar
    case chip

    var pointSize: CGFloat {
        switch self {
        case .toolbar: StudioFieldMetrics.toolbarIconPointSize
        case .chip: StudioFieldMetrics.chipIconPointSize
        }
    }

    var hitSize: CGFloat {
        switch self {
        case .toolbar: StudioFieldMetrics.toolbarIconHitSize
        case .chip: StudioFieldMetrics.chipIconHitSize
        }
    }
}

/// Unified dismiss / remove control. Replaces the ad-hoc `xmark`, `xmark.circle`,
/// and `xmark.circle.fill` buttons previously scattered across tabs, chips, rows,
/// and fields. Use `.outline` for close/dismiss, `.fill` for in-row/field remove.
struct StudioDismissButton: View {
    enum Style {
        case outline
        case fill

        var symbol: String {
            switch self {
            case .outline: "xmark.circle"
            case .fill: "xmark.circle.fill"
            }
        }
    }

    var scale: StudioChromeScale = .toolbar
    var style: Style = .outline
    var help: String = ""
    /// Hierarchical rendering level (`.secondary` for chrome, `.tertiary` for quiet in-row remove).
    var foreground: HierarchicalShapeStyle = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: style.symbol)
                .font(.system(size: scale.pointSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
                .frame(width: scale.hitSize, height: scale.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Unified overflow (ellipsis) menu. Never renders the system menu chevron so it
/// reads as a single icon next to its neighbors. Replaces `StudioToolbarIconMenu`.
struct StudioOverflowMenu<Content: View>: View {
    var scale: StudioChromeScale = .toolbar
    var help: String = "Actions"
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: scale.pointSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: scale.hitSize, height: scale.hitSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}

/// Display-only selection mark (the visual half of a radio). Use inside an existing
/// Button / row for mutually-exclusive "picked" state. `StudioElidableRadio` remains
/// the self-contained interactive version for the axis-tree Elided column.
struct StudioRadioMark: View {
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
        .frame(width: 16, height: 16)
    }
}

/// Canonical linked-value glyph (Format-3 links, fill preview). One size everywhere.
/// Keep this *outside* any `Menu` label — AppKit menu-button chrome can rescale
/// SF Symbols inside the label even when an explicit `.font` is applied.
///
/// - `isEditable: false` (default) — muted / locked (Naming axis, read-only).
/// - `isEditable: true` — primary (changeable link-to target).
struct StudioLinkGlyph: View {
    var isEditable: Bool = false

    var body: some View {
        Image(systemName: "link")
            .font(StudioTypography.linkGlyph)
            .foregroundStyle(isEditable ? .primary : .tertiary)
    }
}

/// Format-3 linked-target suffix for non-Menu contexts (read-only preview rows).
/// For interactive stop rows, compose `StudioLinkGlyph` + target `Text` as siblings
/// beside a `Menu` so the chain is not hosted inside menu chrome.
struct StudioFormat3LinkLabel: View {
    let linkedTargetName: String?
    var placeholder: String = "Link…"

    var body: some View {
        HStack(spacing: 4) {
            StudioLinkGlyph()
            Text(linkedTargetName ?? placeholder)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Canonical "add" affordance label — one glyph size and spacing across add actions.
/// The symbol may vary (`plus`, `folder.badge.plus`, …) but its sizing does not.
struct StudioAddLabel: View {
    let title: String
    var systemImage: String = "plus"
    var foreground: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(StudioTypography.caption)
            .foregroundStyle(foreground)
            .labelStyle(.titleAndIcon)
    }
}

/// Toolbar / header icon control — fixed hit target, consistent symbol size.
struct StudioToolbarIconButton: View {
    let systemName: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: StudioFieldMetrics.toolbarIconPointSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(
                    width: StudioFieldMetrics.toolbarIconHitSize,
                    height: StudioFieldMetrics.toolbarIconHitSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Legacy overflow menu — renders the system menu chevron. Superseded by
/// `StudioOverflowMenu`; call sites migrate in Phase 2. Do not use in new code.
struct StudioToolbarIconMenu<Content: View>: View {
    var help: String = "Actions"
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: StudioFieldMetrics.toolbarIconPointSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(
                    width: StudioFieldMetrics.toolbarIconHitSize,
                    height: StudioFieldMetrics.toolbarIconHitSize
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(help)
    }
}

struct StudioFocusRingSuppression: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

extension View {
    /// Inline axis-tree / table edit chrome — fixed height, no layout shift vs static text.
    func studioInlineEditField(isActive: Bool, rowHeight: CGFloat = StudioFieldMetrics.bodyRowHeight) -> some View {
        padding(.horizontal, isActive ? StudioFieldMetrics.horizontalPadding : 0)
            .frame(height: isActive ? rowHeight : nil, alignment: .center)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: StudioRadius.small)
                        .fill(Color(nsColor: .textBackgroundColor))
                }
            }
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: StudioRadius.small)
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
                }
            }
            .modifier(StudioFocusRingSuppression())
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

struct StudioDirtyDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: StudioFieldMetrics.dirtyDotSize, height: StudioFieldMetrics.dirtyDotSize)
            .frame(width: StudioFieldMetrics.statusBadgeSlot, height: StudioFieldMetrics.statusBadgeSlot)
    }
}

/// Master-font star. Shares `statusBadgeSlot` with `StudioDirtyDot` so the pair
/// centers on the same axis when adjacent in a chip/row.
struct StudioMasterStar: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: StudioFieldMetrics.masterStarPointSize))
            .foregroundStyle(StudioColors.computedHighlight)
            // `star.fill` sits optically low in its glyph box relative to a true
            // circle; nudge so it shares a visual center with StudioDirtyDot.
            .offset(y: -1)
            .frame(width: StudioFieldMetrics.statusBadgeSlot, height: StudioFieldMetrics.statusBadgeSlot)
    }
}

struct StudioRowBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var isWarning: Bool = false
    var selectionStyle: StudioRowSelectionStyle = .fillOnly

    var body: some View {
        RoundedRectangle(cornerRadius: StudioRadius.row)
            .fill(StudioRowChrome.fill(
                isSelected: isSelected,
                isHovered: isHovered,
                isWarning: isWarning
            ))
            .overlay {
                if isSelected && selectionStyle == .fillAndStroke && !isWarning {
                    RoundedRectangle(cornerRadius: StudioRadius.row)
                        .strokeBorder(StudioColors.selectionStroke, lineWidth: 0.5)
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

/// Simple warning caption row for lists (Save Review warnings, etc.).
struct StudioWarningMessage: View {
    let message: String

    var body: some View {
        Text(message)
            .font(StudioTypography.caption)
            .foregroundStyle(StudioColors.warningForeground)
    }
}

struct StudioConflictAlert: View {
    let message: String
    var actionTitle: String = "Resolve…"
    let action: () -> Void

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(StudioTypography.meta)
                .foregroundStyle(StudioColors.warningForeground)

            Text(message)
                .font(StudioTypography.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .studioCompactControl()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

struct StudioInstanceComposedName: View {
    let links: [NamingChainLink]
    let fallback: String
    var included: Bool = true
    var hideElided: Bool = false

    private var displayLinks: [NamingChainLink] {
        hideElided ? links.filter { !$0.elided } : links
    }

    private var showsCollapsedElidedFallback: Bool {
        hideElided && !links.isEmpty && displayLinks.isEmpty
    }

    var body: some View {
        Group {
            if links.isEmpty {
                Text(fallback)
                    .foregroundStyle(included ? .primary : .secondary)
            } else if showsCollapsedElidedFallback {
                Text(fallback)
                    .foregroundStyle(
                        included
                            ? StudioColors.elidedFallbackForeground
                            : StudioColors.elidedFallbackForeground.opacity(0.55)
                    )
            } else {
                composedText(from: displayLinks)
            }
        }
        .font(StudioTypography.bodyMedium)
        .lineLimit(1)
        .help(showsCollapsedElidedFallback ? "Elided fallback — all elidable segments hidden" : "")
    }

    private func composedText(from segments: [NamingChainLink]) -> Text {
        segments.enumerated().reduce(Text("")) { partial, item in
            let (index, link) = item
            var result = partial
            if index > 0 {
                result = result + Text(" ")
            }
            var segment = Text(link.name)
                .foregroundStyle(segmentColor(for: link))
            if link.elided {
                segment = segment.strikethrough(true, color: .secondary)
            }
            return result + segment
        }
    }

    private func segmentColor(for link: NamingChainLink) -> Color {
        switch link.kind {
        case .clarifier:
            return included
                ? StudioColors.clarifierForeground
                : StudioColors.clarifierForeground.opacity(0.55)
        case .code:
            return included
                ? StudioColors.codeForeground
                : StudioColors.codeForeground.opacity(0.55)
        case .registration:
            if link.elided {
                return StudioColors.registrationForeground.opacity(0.45)
            }
            return included
                ? StudioColors.registrationForeground
                : StudioColors.registrationForeground.opacity(0.55)
        case .axis:
            if link.elided { return Color.secondary.opacity(0.55) }
            return included ? Color.primary : Color.secondary
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
        Group {
            if link.kind == .clarifier {
                HStack(spacing: 5) {
                    StudioClarifierPill(
                        label: link.name,
                        showCategory: NamingToken.clarifierDisplayName[link.tag] ?? link.tag,
                        compact: true
                    )
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            } else if link.kind == .code {
                Text(link.name)
                    .font(StudioTypography.monoMeta.weight(.semibold))
                    .foregroundStyle(StudioColors.codeForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(StudioColors.codeBackground, in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            } else {
                Button {
                    onLinkTap?(link.tag)
                } label: {
                    HStack(spacing: 5) {
                        StudioTagPill(
                            text: link.tag,
                            compact: true,
                            role: link.kind == .registration ? .registration : .instance
                        )
                            .opacity(link.elided ? 0.55 : 1)

                        Text(link.name)
                            .font(StudioTypography.bodyMedium)
                            .foregroundStyle(segmentForeground(for: link))
                            .strikethrough(link.elided, color: Color.secondary.opacity(0.45))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func segmentForeground(for link: NamingChainLink) -> Color {
        if link.elided { return Color.secondary.opacity(0.55) }
        switch link.kind {
        case .registration: return StudioColors.registrationForeground
        case .axis: return Color.primary
        case .clarifier: return StudioColors.clarifierForeground
        case .code: return StudioColors.codeForeground
        }
    }
}

/// Inspector axis-coordinate list columns (on-lattice).
/// `elisionWidth` fits the spelled-out “Elidable” header — wider than stop-table “Elided”.
enum InspectorAxisCoordLayout {
    static let badgeWidth: CGFloat = 34
    static let chainWidth: CGFloat = StudioSpace.x3 // 12
    static let valueWidth: CGFloat = 44
    static let elisionWidth: CGFloat = 52
}

struct InspectorAxisCoordinatesView: View {
    let rows: [InspectorAxisCoordRow]
    var selectedStopID: String?
    var onRowTap: ((InspectorAxisCoordRow) -> Void)?
    var onElisionToggle: ((InspectorAxisCoordRow) -> Void)?

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
                    .frame(width: InspectorAxisCoordLayout.chainWidth)

                    Text(StudioFormatting.axisValue(row.value))
                        .font(StudioTypography.monoValue)
                        .foregroundStyle(StudioColors.axisValue)
                        .opacity(row.participatesInNaming ? 1 : 0.55)
                        .monospacedDigit()
                        .frame(width: InspectorAxisCoordLayout.valueWidth, alignment: .trailing)

                    StudioTagPill(text: row.tag, compact: true)
                        .opacity(row.participatesInNaming ? 1 : 0.5)
                        .frame(width: InspectorAxisCoordLayout.badgeWidth, alignment: .center)

                    Text(row.stopName)
                        .font(StudioTypography.body)
                        .foregroundStyle(nameColor(for: row))
                        .strikethrough(row.isElided, color: Color.secondary.opacity(0.45))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .frame(minHeight: StudioFieldMetrics.listRowMinHeight)
                .background {
                    StudioRowBackground(isSelected: isSelected, isHovered: false)
                }
            }
            .buttonStyle(.plain)
            .disabled(onRowTap == nil || row.stopID == nil)

            if showsElisionColumn {
                Group {
                    if row.showsElisionToggle {
                        StudioElidableRadio(isOn: row.isElidable) {
                            onElisionToggle?(row)
                        }
                    }
                }
                .frame(width: InspectorAxisCoordLayout.elisionWidth, alignment: .center)
            }
        }
        .help(row.participatesInNaming
            ? (row.isElided ? "Elided from composed name — focus axis stop" : "Focus this axis stop")
            : "Not in the instance naming grid")
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
