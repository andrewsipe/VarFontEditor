import SwiftUI

enum WorkspaceDragItem: Equatable {
    case font(fontID: String, fromProjectID: String, label: String)
    case project(projectID: String, label: String)

    var sourceProjectID: String {
        switch self {
        case let .font(_, fromProjectID, _):
            fromProjectID
        case let .project(projectID, _):
            projectID
        }
    }
}

enum WorkspaceDropTarget: Equatable {
    case project(String)
    case newProject
    case reorderFont(projectID: String, beforeFontID: String)
    case reorderFontEnd(projectID: String)
}

struct FileChipFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ProjectTabFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ProjectToolbarZoneFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

enum WorkspaceDragSupport {
    static func resolveTarget(
        item: WorkspaceDragItem,
        at location: CGPoint,
        tabFrames: [String: CGRect],
        toolbarFrame: CGRect,
        fontChipFrames: [String: CGRect],
        canSplitFont: Bool
    ) -> WorkspaceDropTarget? {
        if case let .font(draggedID, fromProjectID, _) = item {
            for (key, frame) in fontChipFrames where frame.contains(location) {
                let parts = key.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, String(parts[0]) == fromProjectID else { continue }
                let anchorID = String(parts[1])
                if anchorID == "__end__" {
                    return .reorderFontEnd(projectID: fromProjectID)
                }
                if anchorID != draggedID {
                    return .reorderFont(projectID: fromProjectID, beforeFontID: anchorID)
                }
            }
        }

        let excludedID = item.sourceProjectID

        for (projectID, frame) in tabFrames where frame.contains(location) {
            if projectID != excludedID {
                return .project(projectID)
            }
        }

        if case .font = item,
           canSplitFont,
           toolbarFrame != .zero,
           toolbarFrame.contains(location) {
            let inAnyTab = tabFrames.values.contains { $0.contains(location) }
            if !inAnyTab {
                return .newProject
            }
        }

        return nil
    }
}

/// Drag presentation state isolated from EditorViewModel so pointer moves
/// do not invalidate the full editor UI tree.
@Observable
@MainActor
final class WorkspaceDragCoordinator {
    private(set) var item: WorkspaceDragItem?
    private(set) var isActive = false
    var ghostLocation: CGPoint = .zero
    private(set) var hoveredTarget: WorkspaceDropTarget?

    private var tabFrames: [String: CGRect] = [:]
    private var fontChipFrames: [String: CGRect] = [:]
    private var toolbarFrame: CGRect = .zero
    /// Snapshotted at drag begin so hover hit-testing stays stable while the UI highlights.
    private var dragTabFrames: [String: CGRect] = [:]
    private var dragFontChipFrames: [String: CGRect] = [:]
    private var dragToolbarFrame: CGRect = .zero
    private var dragCanSplitFont = false

    func setTabFrames(_ frames: [String: CGRect]) {
        guard frames != tabFrames else { return }
        tabFrames = frames
    }

    func setToolbarFrame(_ frame: CGRect) {
        guard frame != .zero, frame != toolbarFrame else { return }
        toolbarFrame = frame
    }

    func setFontChipFrames(_ frames: [String: CGRect]) {
        guard frames != fontChipFrames else { return }
        fontChipFrames = frames
    }

    func begin(item: WorkspaceDragItem, location: CGPoint, canSplitFont: Bool) {
        dragTabFrames = tabFrames
        dragFontChipFrames = fontChipFrames
        dragToolbarFrame = toolbarFrame
        dragCanSplitFont = canSplitFont
        self.item = item
        isActive = true
        ghostLocation = location
        hoveredTarget = resolveTarget(for: item, at: location)
    }

    func update(location: CGPoint) {
        guard let item else { return }
        ghostLocation = location
        let newTarget = resolveTarget(for: item, at: location)
        if newTarget != hoveredTarget {
            hoveredTarget = newTarget
        }
    }

    func end() -> (WorkspaceDragItem, WorkspaceDropTarget?)? {
        guard let item else { return nil }
        let target = hoveredTarget
        self.item = nil
        isActive = false
        hoveredTarget = nil
        return (item, target)
    }

    func cancel() {
        item = nil
        isActive = false
        hoveredTarget = nil
    }

    private func resolveTarget(
        for item: WorkspaceDragItem,
        at location: CGPoint
    ) -> WorkspaceDropTarget? {
        WorkspaceDragSupport.resolveTarget(
            item: item,
            at: location,
            tabFrames: isActive ? dragTabFrames : tabFrames,
            toolbarFrame: isActive ? dragToolbarFrame : toolbarFrame,
            fontChipFrames: isActive ? dragFontChipFrames : fontChipFrames,
            canSplitFont: dragCanSplitFont
        )
    }
}

struct WorkspaceDraggableContainer<Content: View>: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    let item: WorkspaceDragItem
    let isDragEnabled: Bool
    let helpText: String
    var onBegin: (() -> Void)?
    var onTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var dragStarted = false

    var body: some View {
        Group {
            if isDragEnabled {
                content()
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard !dragStarted, !workspaceDrag.isActive else { return }
                            onTap?()
                        }
                    )
            } else {
                content()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
            }
        }
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard isDragEnabled, !editor.isBusy else { return }
                if !workspaceDrag.isActive {
                    dragStarted = true
                    onBegin?()
                    editor.beginWorkspaceDrag(item: item, location: value.location)
                } else {
                    editor.updateWorkspaceDrag(location: value.location)
                }
            }
            .onEnded { _ in
                if dragStarted {
                    editor.endWorkspaceDrag()
                }
                dragStarted = false
            }
    }
}

struct WorkspaceDragGhostOverlay: View {
    @Environment(WorkspaceDragCoordinator.self) private var workspaceDrag
    let workspaceOrigin: CGPoint

    var body: some View {
        if let item = workspaceDrag.item {
            Text(label(for: item))
                .font(StudioTypography.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: StudioRadius.chip)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: StudioRadius.chip)
                        .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                .opacity(0.92)
                .position(
                    x: workspaceDrag.ghostLocation.x - workspaceOrigin.x,
                    y: workspaceDrag.ghostLocation.y - workspaceOrigin.y
                )
                .allowsHitTesting(false)
        }
    }

    private func label(for item: WorkspaceDragItem) -> String {
        switch item {
        case let .font(_, _, label), let .project(_, label):
            label
        }
    }
}
