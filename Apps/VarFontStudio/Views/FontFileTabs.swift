import SwiftUI
import VarFontCore

struct FontFileTabs: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        if let project = editor.project, project.fonts.count > 1 {
            Picker("Font file", selection: Binding(
                get: { editor.selectedFontID ?? "" },
                set: { editor.selectFont(id: $0) }
            )) {
                ForEach(project.fonts) { font in
                    Text(shortName(for: font)).tag(font.id)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .font(StudioTypography.caption)
            .padding(.horizontal, StudioSpacing.panelHorizontal)
            .padding(.top, StudioSpacing.panelVertical)
        }
    }

    private func shortName(for font: FontDocument) -> String {
        URL(fileURLWithPath: font.sourcePath).deletingPathExtension().lastPathComponent
    }
}
