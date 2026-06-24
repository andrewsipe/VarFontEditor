import AppKit
import SwiftUI

@main
struct VarFontStudioApp: App {
    @StateObject private var editor = EditorViewModel()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            MainEditorView()
                .environmentObject(editor)
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
                .disabled(editor.project == nil)
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
        }
    }
}
