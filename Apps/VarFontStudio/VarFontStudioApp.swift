import AppKit
import SwiftUI

@main
struct VarFontStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            mainWindowCommands
        }

        WindowGroup(id: "save-review", for: String.self) { $projectID in
            if let projectID {
                SaveReviewWindow(projectID: projectID)
                    .environmentObject(editor)
                    .environmentObject(layout)
            }
        }
        .defaultSize(width: 960, height: 720)
    }

    @CommandsBuilder
    private var mainWindowCommands: some Commands {
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
                Button("Save") {
                    editor.save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!editor.canSave || editor.isSaveActionBlocked)

                Button("Save Copy…") {
                    editor.saveCopy()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!editor.canSave || editor.isSaveActionBlocked)

                if let projectID = editor.activeProjectID,
                   editor.openProjects.first(where: { $0.id == projectID })?.document.fonts.count ?? 0 > 1 {
                    Button("Save All Files…") {
                        editor.saveAllFiles(inProjectID: projectID)
                    }
                    .disabled(!editor.canSave || editor.isSaveActionBlocked)
                    .help("Write every file in this project that has unsaved edits")
                }

                Divider()

                Button("Open Save Review Window") {
                    editor.presentSaveReviewWindow()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!editor.canPreviewSaveReview)
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

                Divider()

                Toggle("Auto-Hide Inspector", isOn: $layout.inspectorAutoHide)
                    .disabled(!layout.showInspector)

                Divider()

                Button("Save Review Window") {
                    editor.presentSaveReviewWindow()
                }
                .keyboardShortcut("4", modifiers: [.command, .control])
                .disabled(!editor.canPreviewSaveReview)
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

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        SaveReviewWindowLifecycle.closeRestoredWindows()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SaveReviewWindowLifecycle.scheduleCloseRestoredWindows()
    }
}
