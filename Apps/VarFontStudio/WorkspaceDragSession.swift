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

/// Active project's FILE chip row — external drops add fonts to this project.
struct ProjectFileSubBarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

/// Inspector column — external drops add fonts to the active project.
struct InspectorPanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct AxisTreePanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct InstancesPanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

/// Inspector FILES list — kept for fine-grained hit testing within the inspector.
struct InspectorFilesDropFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

enum WorkspaceDragSupport {
    static func resolveInternalTarget(
        item: WorkspaceDragItem,
        at location: CGPoint,
        tabFrames: [String: CGRect],
        toolbarFrame: CGRect,
        fontChipFrames: [String: CGRect],
        canSplitFont: Bool
    ) -> WorkspaceDropTarget? {
        resolveInternalTarget(
            item: item,
            at: location,
            tabFrames: tabFrames,
            toolbarFrame: toolbarFrame,
            fontChipFrameGroups: [fontChipFrames],
            canSplitFont: canSplitFont
        )
    }

    static func resolveInternalTarget(
        item: WorkspaceDragItem,
        at location: CGPoint,
        tabFrames: [String: CGRect],
        toolbarFrame: CGRect,
        fontChipFrameGroups: [[String: CGRect]],
        canSplitFont: Bool
    ) -> WorkspaceDropTarget? {
        if case let .font(draggedID, fromProjectID, _) = item {
            for frames in fontChipFrameGroups {
                for (key, frame) in frames where frame.contains(location) {
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

    /// Resolve where external font files from Finder should land.
    static func resolveExternalFileTarget(
        at location: CGPoint,
        tabFrames: [String: CGRect],
        toolbarFrame: CGRect,
        fileSubBarFrame: CGRect,
        inspectorPanelFrame: CGRect,
        activeProjectID: String?
    ) -> WorkspaceDropTarget? {
        for (projectID, frame) in tabFrames where frame.contains(location) {
            return .project(projectID)
        }

        if let activeProjectID,
           fileSubBarFrame != .zero,
           fileSubBarFrame.contains(location) {
            return .project(activeProjectID)
        }

        if let activeProjectID,
           inspectorPanelFrame != .zero,
           inspectorPanelFrame.contains(location) {
            return .project(activeProjectID)
        }

        if toolbarFrame != .zero, toolbarFrame.contains(location) {
            let inAnyTab = tabFrames.values.contains { $0.contains(location) }
            if !inAnyTab {
                return .newProject
            }
        }

        return .newProject
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

    private(set) var isExternalFileDropActive = false
    private(set) var externalFileCount = 0
    var externalDropLocation: CGPoint = .zero

    private var tabFrames: [String: CGRect] = [:]
    /// FILE sub-bar chip frames (keys `"projectID:fontID"` / `"projectID:__end__"`).
    private var fileSubBarChipFrames: [String: CGRect] = [:]
    /// Project inspector Files list row frames (same key scheme; kept separate so global
    /// frames for the same font on two surfaces don't clobber each other).
    private var inspectorFileChipFrames: [String: CGRect] = [:]
    private var toolbarFrame: CGRect = .zero
    private var fileSubBarFrame: CGRect = .zero
    private var inspectorPanelFrame: CGRect = .zero
    private var axisTreeFrame: CGRect = .zero
    private var instancesFrame: CGRect = .zero

    private var dragTabFrames: [String: CGRect] = [:]
    private var dragFileSubBarChipFrames: [String: CGRect] = [:]
    private var dragInspectorFileChipFrames: [String: CGRect] = [:]
    private var dragToolbarFrame: CGRect = .zero
    private var dragCanSplitFont = false

    private var liveFontChipFrameGroups: [[String: CGRect]] {
        [fileSubBarChipFrames, inspectorFileChipFrames]
    }

    private var dragFontChipFrameGroups: [[String: CGRect]] {
        [dragFileSubBarChipFrames, dragInspectorFileChipFrames]
    }

    func setTabFrames(_ frames: [String: CGRect]) {
        guard frames != tabFrames else { return }
        tabFrames = frames
    }

    func setToolbarFrame(_ frame: CGRect) {
        guard frame != .zero, frame != toolbarFrame else { return }
        toolbarFrame = frame
    }

    enum FontChipFrameSource {
        case fileSubBar
        case inspectorFiles
    }

    func setFontChipFrames(_ frames: [String: CGRect], source: FontChipFrameSource) {
        switch source {
        case .fileSubBar:
            guard frames != fileSubBarChipFrames else { return }
            fileSubBarChipFrames = frames
        case .inspectorFiles:
            guard frames != inspectorFileChipFrames else { return }
            inspectorFileChipFrames = frames
        }
    }

    func setFileSubBarFrame(_ frame: CGRect) {
        guard frame != .zero, frame != fileSubBarFrame else { return }
        fileSubBarFrame = frame
    }

    func setInspectorPanelFrame(_ frame: CGRect) {
        guard frame != .zero, frame != inspectorPanelFrame else { return }
        inspectorPanelFrame = frame
    }

    func setAxisTreeFrame(_ frame: CGRect) {
        guard frame != .zero, frame != axisTreeFrame else { return }
        axisTreeFrame = frame
    }

    func setInstancesFrame(_ frame: CGRect) {
        guard frame != .zero, frame != instancesFrame else { return }
        instancesFrame = frame
    }

    // MARK: - Internal workspace drag

    func begin(item: WorkspaceDragItem, location: CGPoint, canSplitFont: Bool) {
        dragTabFrames = tabFrames
        dragFileSubBarChipFrames = fileSubBarChipFrames
        dragInspectorFileChipFrames = inspectorFileChipFrames
        dragToolbarFrame = toolbarFrame
        dragCanSplitFont = canSplitFont
        self.item = item
        isActive = true
        ghostLocation = location
        hoveredTarget = resolveInternalTarget(for: item, at: location)
    }

    func update(location: CGPoint) {
        guard let item else { return }
        ghostLocation = location
        let newTarget = resolveInternalTarget(for: item, at: location)
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

    // MARK: - External file drop (Finder → app)

    func beginExternalFileDrop(fileCount: Int, at location: CGPoint) {
        isExternalFileDropActive = true
        externalFileCount = fileCount
        externalDropLocation = location
        hoveredTarget = resolveExternalFileTarget(at: location, activeProjectID: nil)
    }

    func updateExternalFileDrop(
        at location: CGPoint,
        activeProjectID: String?
    ) {
        guard isExternalFileDropActive else { return }
        externalDropLocation = location
        let newTarget = resolveExternalFileTarget(at: location, activeProjectID: activeProjectID)
        if newTarget != hoveredTarget {
            hoveredTarget = newTarget
        }
    }

    func endExternalFileDrop() -> WorkspaceDropTarget? {
        guard isExternalFileDropActive else { return nil }
        let target = hoveredTarget
        isExternalFileDropActive = false
        externalFileCount = 0
        hoveredTarget = nil
        return target
    }

    func cancelExternalFileDrop() {
        isExternalFileDropActive = false
        externalFileCount = 0
        hoveredTarget = nil
    }

    func isHighlightingProject(_ projectID: String) -> Bool {
        guard let hoveredTarget else { return false }
        if case .project(let id) = hoveredTarget {
            return id == projectID
        }
        return false
    }

    /// True when the cursor is physically over a project tab (not merely resolved to that project).
    func isHoveringProjectTab(_ projectID: String) -> Bool {
        guard isExternalFileDropActive,
              let frame = tabFrames[projectID] else { return false }
        return frame.contains(externalDropLocation)
    }

    var isHighlightingNewProject: Bool {
        hoveredTarget == .newProject
    }

    // MARK: - External drop zone highlights

    private var isOverAxisTreePanel: Bool {
        axisTreeFrame != .zero && axisTreeFrame.contains(externalDropLocation)
    }

    private var isOverInstancesPanel: Bool {
        instancesFrame != .zero && instancesFrame.contains(externalDropLocation)
    }

    private var isOverInspectorPanel: Bool {
        inspectorPanelFrame != .zero && inspectorPanelFrame.contains(externalDropLocation)
    }

    private var isOverProjectToolbar: Bool {
        toolbarFrame != .zero && toolbarFrame.contains(externalDropLocation)
    }

    private var isOverFileSubBar: Bool {
        fileSubBarFrame != .zero && fileSubBarFrame.contains(externalDropLocation)
    }

    private var isOverMainWorkspace: Bool {
        isOverAxisTreePanel || isOverInstancesPanel
    }

    var shouldHighlightAxisTreePanel: Bool {
        guard isExternalFileDropActive, hoveredTarget == .newProject else { return false }
        return isOverMainWorkspace
    }

    var shouldHighlightInstancesPanel: Bool {
        guard isExternalFileDropActive, hoveredTarget == .newProject else { return false }
        return isOverMainWorkspace
    }

    var shouldHighlightProjectToolbarRow: Bool {
        guard isExternalFileDropActive, hoveredTarget == .newProject else { return false }
        return isOverMainWorkspace || isOverProjectToolbar
    }

    func shouldHighlightInspectorPanel(activeProjectID: String?) -> Bool {
        guard isExternalFileDropActive,
              let activeProjectID,
              case .project(let id) = hoveredTarget,
              id == activeProjectID else { return false }
        return isOverInspectorPanel
    }

    func shouldHighlightFileSubBarRow(activeProjectID: String?) -> Bool {
        guard isExternalFileDropActive,
              let activeProjectID,
              case .project(let id) = hoveredTarget,
              id == activeProjectID else { return false }
        return isOverFileSubBar || isOverInspectorPanel
    }

    func shouldHighlightProjectTab(_ projectID: String, activeProjectID: String?) -> Bool {
        guard isExternalFileDropActive,
              case .project(let id) = hoveredTarget,
              id == projectID else { return false }
        if isHoveringProjectTab(projectID) { return true }
        if projectID == activeProjectID, isOverFileSubBar || isOverInspectorPanel {
            return true
        }
        return false
    }

    private func resolveInternalTarget(
        for item: WorkspaceDragItem,
        at location: CGPoint
    ) -> WorkspaceDropTarget? {
        WorkspaceDragSupport.resolveInternalTarget(
            item: item,
            at: location,
            tabFrames: isActive ? dragTabFrames : tabFrames,
            toolbarFrame: isActive ? dragToolbarFrame : toolbarFrame,
            fontChipFrameGroups: isActive ? dragFontChipFrameGroups : liveFontChipFrameGroups,
            canSplitFont: dragCanSplitFont
        )
    }

    private func resolveExternalFileTarget(
        at location: CGPoint,
        activeProjectID: String?
    ) -> WorkspaceDropTarget? {
        WorkspaceDragSupport.resolveExternalFileTarget(
            at: location,
            tabFrames: tabFrames,
            toolbarFrame: toolbarFrame,
            fileSubBarFrame: fileSubBarFrame,
            inspectorPanelFrame: inspectorPanelFrame,
            activeProjectID: activeProjectID
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
                    // Prefer drag over enclosing ScrollView pans so FILE chips / inspector
                    // rows can reorder; taps still fire when the drag never starts.
                    .highPriorityGesture(dragGesture)
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
        ZStack {
            if let item = workspaceDrag.item {
                dragGhost(for: item)
            }

            if workspaceDrag.isExternalFileDropActive,
               let target = workspaceDrag.hoveredTarget {
                externalDropBadge(for: target)
            }
        }
        .allowsHitTesting(false)
    }

    private func dragGhost(for item: WorkspaceDragItem) -> some View {
        HStack(spacing: 5) {
            if let symbol = badgeSymbol(for: workspaceDrag.hoveredTarget) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(badgeColor(for: workspaceDrag.hoveredTarget))
            }
            Text(label(for: item))
                .font(StudioTypography.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
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
    }

    private func externalDropBadge(for target: WorkspaceDropTarget) -> some View {
        HStack(spacing: 4) {
            Image(systemName: badgeSymbol(for: target) ?? "plus.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(externalBadgeLabel(for: target))
                .font(StudioTypography.meta)
                .fontWeight(.medium)
        }
        .foregroundStyle(badgeColor(for: target))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .position(
            x: workspaceDrag.externalDropLocation.x - workspaceOrigin.x + 24,
            y: workspaceDrag.externalDropLocation.y - workspaceOrigin.y - 20
        )
    }

    private func label(for item: WorkspaceDragItem) -> String {
        switch item {
        case let .font(_, _, label), let .project(_, label):
            label
        }
    }

    private func badgeSymbol(for target: WorkspaceDropTarget?) -> String? {
        switch target {
        case .project:
            return "plus.circle.fill"
        case .newProject:
            return "folder.badge.plus"
        case .reorderFont, .reorderFontEnd:
            return "arrow.left.arrow.right"
        case nil:
            return nil
        }
    }

    private func badgeColor(for target: WorkspaceDropTarget?) -> Color {
        switch target {
        case .newProject:
            return StudioColors.dropNewProject
        case .project:
            return StudioColors.dropAddExisting
        case .reorderFont, .reorderFontEnd:
            return .secondary
        case nil:
            return .secondary
        }
    }

    private func externalBadgeLabel(for target: WorkspaceDropTarget) -> String {
        switch target {
        case .project:
            let count = workspaceDrag.externalFileCount
            return count == 1 ? "Add font" : "Add \(count) fonts"
        case .newProject:
            let count = workspaceDrag.externalFileCount
            return count == 1 ? "New project" : "New project · \(count) files"
        case .reorderFont, .reorderFontEnd:
            return ""
        }
    }
}
