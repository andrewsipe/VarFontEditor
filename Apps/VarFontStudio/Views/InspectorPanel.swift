import SwiftUI
import VarFontCore

struct InspectorPanel: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        Group {
            if let instance = editor.selectedInstance {
                instanceInspector(instance)
            } else {
                ContentUnavailableView(
                    "No Instance Selected",
                    systemImage: "sidebar.right",
                    description: Text("Select a row in the instance list to inspect naming and coordinates.")
                )
            }
        }
        .navigationTitle("Inspector")
    }

    private func instanceInspector(_ instance: PlannedInstance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioSpacing.sectionGap + 4) {
                StudioInspectorBlock(title: "Composed name") {
                    Text(instance.composedName)
                        .font(StudioTypography.emphasis)
                        .textSelection(.enabled)
                }

                StudioInspectorBlock(title: "Naming chain") {
                    if instance.namingChain.isEmpty {
                        Text("No naming chain entries")
                            .font(StudioTypography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(instance.namingChain.enumerated()), id: \.offset) { _, link in
                                HStack(spacing: StudioSpacing.controlGap) {
                                    StudioTagPill(text: link.tag, compact: true)
                                    Text(link.name)
                                        .font(StudioTypography.body)
                                    Spacer(minLength: 0)
                                    if link.elided {
                                        Text("elided")
                                            .font(StudioTypography.meta)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                StudioInspectorBlock(title: "Coordinates") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sortedCoordKeys(instance.coords), id: \.self) { tag in
                            let pinned = !editor.axisParticipatesInInstanceGrid(tag: tag)
                            StudioKeyValueRow(
                                key: tag,
                                value: StudioFormatting.axisValue(instance.coords[tag] ?? 0),
                                valueFont: StudioTypography.monoValue,
                                valueColor: StudioColors.axisValue,
                                muted: pinned
                            )
                            .help(pinned ? "Pinned — excluded from the instance grid" : "")
                        }
                    }
                }

                StudioInspectorBlock(title: "Instance key") {
                    Text(instance.key)
                        .font(StudioTypography.monoMeta)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let warnings = editor.instancePlan?.warnings, !warnings.isEmpty {
                    StudioInspectorBlock(title: "Plan warnings") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning.message, systemImage: "exclamationmark.triangle")
                                    .font(StudioTypography.meta)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioPanelPadding()
        }
    }

    private func sortedCoordKeys(_ coords: [String: Double]) -> [String] {
        coords.keys.sorted()
    }
}
