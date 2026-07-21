import SwiftUI

/// Keyboard shortcuts reference for alpha testers.
struct StudioShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct ShortcutRow: Identifiable {
        let id = UUID()
        let action: String
        let keys: String
    }

    private let sections: [(title: String, rows: [ShortcutRow])] = [
        ("File", [
            ShortcutRow(action: "Open project", keys: "⌘⌥O"),
            ShortcutRow(action: "Open font", keys: "⌘O"),
            ShortcutRow(action: "Add font to project", keys: "⌘⇧O"),
            ShortcutRow(action: "Save project", keys: "⌘S"),
            ShortcutRow(action: "Save project as", keys: "⌘⇧S"),
            ShortcutRow(action: "Export (choose path)", keys: "⌘E"),
            ShortcutRow(action: "Open review window", keys: "⌘⇧R"),
        ]),
        ("Edit", [
            ShortcutRow(action: "Undo", keys: "⌘Z"),
            ShortcutRow(action: "Redo", keys: "⌘⇧Z"),
            ShortcutRow(action: "Find instances", keys: "⌘F"),
        ]),
        ("View", [
            ShortcutRow(action: "Toggle axis tree", keys: "⌃⌘1"),
            ShortcutRow(action: "Toggle instances", keys: "⌃⌘2"),
            ShortcutRow(action: "Toggle inspector", keys: "⌃⌘3"),
            ShortcutRow(action: "Toggle review window", keys: "⌃⌘4"),
        ]),
        ("Instances", [
            ShortcutRow(action: "Include all shown", keys: "⌥⌘I"),
            ShortcutRow(action: "Exclude all shown", keys: "⌥⌘E"),
            ShortcutRow(action: "Include selection", keys: "⌘⇧I"),
            ShortcutRow(action: "Exclude selection", keys: "⌘⇧E"),
        ]),
        ("Preferences", [
            ShortcutRow(action: "OpenType feature name IDs (app default)", keys: "Preferences menu"),
            ShortcutRow(action: "Preserve vs reflow to 256+ (this project)", keys: "Review tab bar"),
        ]),
    ]

    private var workflowNotes: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.rowGap) {
            Text("WORKFLOW")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
            Text("Save writes the .varf project file (legacy .varfont still opens). Export writes patched font binaries — use Export All… to keep original filenames in a folder. Review (⌘⇧R) shows STAT, fvar, and name slots with a nameID column; OpenType label reflow is optional under Preferences, or override per project in Review.")
                .font(StudioTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.x4) {
            VStack(alignment: .leading, spacing: StudioSpacing.tightGap) {
                Text("VarFont Studio Shortcuts")
                    .font(StudioTypography.emphasis)
                Text("Alpha build — Save is the project file; Export writes patched fonts beside the source or into a folder you choose.")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    workflowNotes

                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: StudioSpacing.controlGap) {
                            Text(section.title.uppercased())
                                .font(StudioTypography.sectionLabel)
                                .foregroundStyle(.secondary)
                            ForEach(section.rows) { row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.action)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(row.keys)
                                        .font(StudioTypography.monoMeta)
                                        .foregroundStyle(.secondary)
                                }
                                .font(StudioTypography.body)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(StudioSpacing.sheetOuterPadding)
        .frame(width: 460, height: 540)
        .preferredColorScheme(.dark)
    }
}
