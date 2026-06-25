import SwiftUI
import VarFontCore

/// Tier-2 file switcher below the project toolbar.
struct ProjectFileSubBar: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        Group {
            if editor.hasOpenProjects, let project = editor.project, !project.fonts.isEmpty {
                HStack(spacing: StudioSpacing.controlGap) {
                    Text("FILE")
                        .font(StudioTypography.sectionLabel)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(project.fonts) { font in
                                fileChip(font)
                            }
                        }
                    }
                }
                .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
                .padding(.vertical, 5)
                .background(.bar.opacity(0.65))
            }
        }
    }

    private func fileChip(_ font: FontDocument) -> some View {
        let isSelected = editor.selectedFontID == font.id
        let name = editor.fontBasename(for: font)

        return Button {
            editor.selectFont(id: font.id)
        } label: {
            Text(name)
                .font(StudioTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? StudioColors.selectionFill : Color.primary.opacity(0.04),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }
}
