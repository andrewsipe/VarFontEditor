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
                .onAppear {
                    appDelegate.editor = editor
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        await editor.openProjectFile(at: url)
                    }
                }
        }
        .commands {
            mainWindowCommands
        }

        Settings {
            StudioSettingsView()
                .environmentObject(layout)
                .environmentObject(editor)
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
                Button("Open Project…") {
                    editor.presentOpenProjectPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])

                Button("Open Font…") {
                    editor.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Add Font to Project…") {
                    editor.presentAddFontPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!editor.hasOpenProjects)

                Divider()

                Button("Save Project") {
                    editor.saveProject()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!editor.canSaveProject)

                Button("Save Project As…") {
                    editor.saveProjectAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!editor.hasOpenProjects)

                Divider()

                if editor.canSaveToRememberedPathForSelection {
                    Button("Export As…") {
                        editor.saveCopy()
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!editor.canSave || editor.isSaveActionBlocked)
                    .help("Choose a new path for this font")

                    Button("Export") {
                        editor.save()
                    }
                    .disabled(!editor.canSave || editor.isSaveActionBlocked)
                    .help("Write to the last export path")
                } else {
                    Button("Export…") {
                        editor.saveCopy()
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!editor.canSave || editor.isSaveActionBlocked)
                }

                if let projectID = editor.activeProjectID,
                   editor.openProjects.first(where: { $0.id == projectID })?.document.fonts.count ?? 0 > 1 {
                    Button("Export All…") {
                        editor.saveAllFiles(inProjectID: projectID)
                    }
                    .disabled(!editor.canSave || editor.isSaveActionBlocked)
                    .help("Export every file in this project to a folder. Picking the source folder creates a Patched subfolder.")
                }

                Button("Export to Original…") {
                    editor.requestSaveToOriginal()
                }
                .disabled(!editor.canSave || editor.isSaveActionBlocked)
                .help("Overwrite the source font file after confirmation")

                Divider()

                Button("Open Review…") {
                    editor.presentSaveReviewWindow()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!editor.canPreviewSaveReview)
            }

            CommandGroup(replacing: .help) {
                Button("VarFont Studio Shortcuts…") {
                    editor.presentShortcutsHelp()
                }
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

            CommandGroup(after: .textEditing) {
                Button("Find Instances…") {
                    editor.requestInstanceSearchFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(editor.selectedFont == nil)
            }

            CommandGroup(replacing: .sidebar) {
                Toggle("Axis Tree", isOn: $layout.showAxisTree)
                    .keyboardShortcut("1", modifiers: [.command, .control])

                Toggle("Instances", isOn: $layout.showInstances)
                    .keyboardShortcut("2", modifiers: [.command, .control])

                Toggle("Inspector", isOn: $layout.showInspector)
                    .keyboardShortcut("3", modifiers: [.command, .control])

                Divider()

                Button("Toggle Review Window") {
                    editor.toggleSaveReviewWindow()
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

                Divider()

                Toggle(
                    "Code Naming",
                    isOn: Binding(
                        get: { editor.isCodeNamingEnabled },
                        set: { editor.setCodeNamingEnabled($0) }
                    )
                )
                .disabled(editor.project == nil)
            }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var editor: EditorViewModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        SaveReviewWindowLifecycle.closeRestoredWindows()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SaveReviewWindowLifecycle.scheduleCloseRestoredWindows()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let editor else { return .terminateNow }
        if !editor.handleApplicationTerminateRequest() {
            return .terminateLater
        }
        editor.completeApplicationTermination()
        return .terminateLater
    }
}
