import SwiftUI
import VarFontCore

struct ProjectTabAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ProjectToolbar: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Binding var openMenuProjectID: String?

    var body: some View {
        HStack(spacing: StudioSpacing.controlGap) {
            if editor.hasOpenProjects {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(editor.openProjects) { openProject in
                            projectTab(openProject)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                editor.presentOpenPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StudioRadius.chip))
            }
            .buttonStyle(.plain)
            .help("New project — open a variable font")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, StudioSpacing.panelHorizontal + 4)
        .padding(.vertical, StudioSpacing.toolbarVertical)
        .background(.bar)
    }

    private func projectTab(_ openProject: OpenProject) -> some View {
        let isActive = editor.activeProjectID == openProject.id
        let isOpen = openMenuProjectID == openProject.id

        return Button {
            if isActive && isOpen {
                openMenuProjectID = nil
            } else {
                editor.activateProject(id: openProject.id)
                openMenuProjectID = openProject.id
            }
        } label: {
            HStack(spacing: 5) {
                Text(editor.projectTabLabel(for: openProject))
                    .font(StudioTypography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)

                Text("\(openProject.document.fonts.count)")
                    .font(StudioTypography.monoMeta)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                tabFill(isActive: isActive, isOpen: isOpen),
                in: RoundedRectangle(cornerRadius: StudioRadius.chip)
            )
        }
        .buttonStyle(.plain)
        .anchorPreference(key: ProjectTabAnchorKey.self, value: .bounds) { anchor in
            [openProject.id: anchor]
        }
    }

    private func tabFill(isActive: Bool, isOpen: Bool) -> Color {
        if isActive || isOpen {
            return StudioColors.selectionFill
        }
        return Color.primary.opacity(0.04)
    }
}
