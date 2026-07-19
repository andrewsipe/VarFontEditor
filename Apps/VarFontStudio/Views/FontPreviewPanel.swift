import AppKit
import SwiftUI
import VarFontCore

private enum FontPreviewAlignment: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var help: String {
        switch self {
        case .leading: "Align left"
        case .center: "Align center"
        case .trailing: "Align right"
        }
    }
}

/// Live source-font glyph preview for the editor footer.
struct FontPreviewPanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("studio.fontPreviewSample") private var sampleText = "Handgloves"
    @AppStorage("studio.fontPreviewSize") private var previewSize = 48.0
    @AppStorage("studio.fontPreviewAlignment") private var alignmentRaw = FontPreviewAlignment.leading.rawValue

    private var alignment: FontPreviewAlignment {
        get { FontPreviewAlignment(rawValue: alignmentRaw) ?? .leading }
        nonmutating set { alignmentRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .fixedSize(horizontal: false, vertical: true)
            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
                .fixedSize(horizontal: false, vertical: true)
        }
        // Fill the shared footer body height so leftover space goes into the canvas,
        // not as empty padding under the status bar.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            TextField("Sample text", text: $sampleText)
                .textFieldStyle(.plain)
                .font(StudioTypography.bodyMedium)
                .padding(.horizontal, StudioFieldMetrics.horizontalPadding)
                .frame(height: StudioFieldMetrics.bodyMediumRowHeight)
                .background(StudioColors.surfaceInset, in: RoundedRectangle(cornerRadius: StudioRadius.control))
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Text("Size")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)

                Slider(value: $previewSize, in: 24...72, step: 1)
                    .frame(width: 100)
                    .controlSize(.mini)

                Text("\(Int(previewSize.rounded()))")
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
            }

            alignmentPicker
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 6)
        .padding(.vertical, StudioSpacing.toolbarVertical)
    }

    private var alignmentPicker: some View {
        HStack(spacing: 1) {
            ForEach(FontPreviewAlignment.allCases) { option in
                Button {
                    alignment = option
                } label: {
                    Image(systemName: option.systemImage)
                        .font(StudioTypography.meta)
                        .foregroundStyle(alignment == option ? Color.accentColor : .secondary)
                        .frame(width: 24, height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: StudioRadius.small)
                                .fill(alignment == option ? Color.accentColor.opacity(0.12) : Color.clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: StudioRadius.small))
                }
                .buttonStyle(.plain)
                .help(option.help)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: StudioRadius.control))
    }

    private var canvas: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.118)

            if let nsFont = previewFont {
                Text(sampleText.isEmpty ? " " : sampleText)
                    .font(Font(nsFont))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(alignment.textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment.frameAlignment)
                    .padding(.horizontal, StudioSpacing.panelHorizontal + 6)
                    .padding(.vertical, 10)
                    .opacity(editor.isPreviewHoverPeeking ? 0.92 : 1)
            } else {
                Text(unavailableMessage)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, StudioSpacing.panelHorizontal + 6)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var statusBar: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            if let instance = editor.previewActiveInstance {
                Text(instance.composedName)
                    .font(StudioTypography.caption)
                    .foregroundStyle(editor.isPreviewHoverPeeking ? Color.accentColor : .primary)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(.quaternary)

                Text(coordsCaption(for: instance))
                    .font(StudioTypography.monoMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Select an instance to preview")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Text(editor.isPreviewHoverPeeking ? "Peek · hover" : "Source · live")
                .font(StudioTypography.meta)
                .foregroundStyle(statusPillForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .strokeBorder(
                            editor.isPreviewHoverPeeking
                                ? Color.accentColor.opacity(0.35)
                                : Color.secondary.opacity(0.22),
                            lineWidth: 1
                        )
                        .background(
                            Capsule().fill(
                                editor.isPreviewHoverPeeking
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        )
                )
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 6)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private var statusPillForeground: some ShapeStyle {
        if editor.isPreviewHoverPeeking {
            return AnyShapeStyle(Color.accentColor)
        }
        return AnyShapeStyle(.tertiary)
    }

    private var previewFont: NSFont? {
        guard let font = editor.selectedFont,
              let fontID = editor.selectedFontID,
              let instance = editor.previewActiveInstance else {
            return nil
        }
        return editor.fontPreviewCache.nsFont(
            fontID: fontID,
            bookmark: editor.sourceBookmarks[fontID],
            sourcePath: font.sourcePath,
            coords: instance.coords,
            size: CGFloat(previewSize)
        )
    }

    private var unavailableMessage: String {
        if editor.selectedFont == nil {
            return "Open a variable font to preview."
        }
        if editor.previewActiveInstance == nil {
            return "Select an instance to preview."
        }
        return "Preview unavailable for this font file."
    }

    private func coordsCaption(for instance: PlannedInstance) -> String {
        let order = editor.selectedFont?.axes.map(\.tag) ?? Array(instance.coords.keys).sorted()
        return StudioFormatting.coordPairs(coords: instance.coords, namingOrder: order)
            .joined(separator: " · ")
            .replacingOccurrences(of: "=", with: ":")
    }
}
