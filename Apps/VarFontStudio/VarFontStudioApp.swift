import AppKit
import SwiftUI

@main
struct VarFontStudioApp: App {
    @StateObject private var editor = EditorViewModel()
    @StateObject private var layout = EditorLayoutPreferences()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            MainEditorView()
                .environmentObject(editor)
                .environmentObject(layout)
                .environment(editor.workspaceDrag)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Font…") {
                    editor.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Add Font to Project…") {
                    editor.presentAddFontPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!editor.hasOpenProjects)
            }

            CommandGroup(after: .saveItem) {
                Button("Save Copy…") {
                    editor.saveCopy()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!editor.canSave)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    editor.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!editor.canUndo)

                Button("Redo") {
                    editor.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!editor.canRedo)
            }

            CommandGroup(replacing: .sidebar) {
                Toggle("Axis Tree", isOn: $layout.showAxisTree)
                    .keyboardShortcut("1", modifiers: [.command, .control])

                Toggle("Instances", isOn: $layout.showInstances)
                    .keyboardShortcut("2", modifiers: [.command, .control])

                Toggle("Inspector", isOn: $layout.showInspector)
                    .keyboardShortcut("3", modifiers: [.command, .control])
            }

            CommandMenu("Instances") {
                Button(InstanceInclusionCommands.includeAllShownTitle) {
                    editor.setAllVisibleInstancesIncluded(true)
                }
                .keyboardShortcut(InstanceInclusionCommands.includeAllShownShortcut)
                .disabled(editor.filteredInstances.isEmpty)

                Button(InstanceInclusionCommands.excludeAllShownTitle) {
                    editor.setAllVisibleInstancesIncluded(false)
                }
                .keyboardShortcut(InstanceInclusionCommands.excludeAllShownShortcut)
                .disabled(editor.filteredInstances.isEmpty)

                Divider()

                Button(InstanceInclusionCommands.includeSelectionTitle) {
                    editor.setInstancesIncluded(keys: editor.activeInstanceSelection, included: true)
                }
                .keyboardShortcut(InstanceInclusionCommands.includeSelectionShortcut)
                .disabled(editor.activeInstanceSelection.isEmpty)

                Button(InstanceInclusionCommands.excludeSelectionTitle) {
                    editor.setInstancesIncluded(keys: editor.activeInstanceSelection, included: false)
                }
                .keyboardShortcut(InstanceInclusionCommands.excludeSelectionShortcut)
                .disabled(editor.activeInstanceSelection.isEmpty)
            }
        }
    }
}
