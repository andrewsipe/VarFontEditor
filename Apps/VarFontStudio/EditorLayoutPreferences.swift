import Foundation
import SwiftUI

@MainActor
final class EditorLayoutPreferences: ObservableObject {
    @Published var showAxisTree: Bool {
        didSet {
            UserDefaults.standard.set(showAxisTree, forKey: Keys.axisTree)
            ensureAtLeastOnePanelVisible()
        }
    }

    @Published var showInstances: Bool {
        didSet {
            UserDefaults.standard.set(showInstances, forKey: Keys.instances)
            ensureAtLeastOnePanelVisible()
        }
    }

    @Published var showInspector: Bool {
        didSet {
            UserDefaults.standard.set(showInspector, forKey: Keys.inspector)
            if !showInspector {
                inspectorPinnedOpen = false
            }
            ensureAtLeastOnePanelVisible()
        }
    }

    /// Axis tree collapsed to a leading rail (canvas-first layout).
    @Published var axisTreeCollapsed: Bool {
        didSet { UserDefaults.standard.set(axisTreeCollapsed, forKey: Keys.axisTreeCollapsed) }
    }

    /// When true, inspector only occupies space when an instance is selected (or user pins it open).
    @Published var inspectorAutoHide: Bool {
        didSet { UserDefaults.standard.set(inspectorAutoHide, forKey: Keys.inspectorAutoHide) }
    }

    /// User explicitly opened the inspector via the View menu while nothing was selected.
    @Published var inspectorPinnedOpen: Bool = false

    @Published var axisTreeWidth: CGFloat {
        didSet { UserDefaults.standard.set(axisTreeWidth, forKey: Keys.axisTreeWidth) }
    }

    @Published var inspectorWidth: CGFloat {
        didSet { UserDefaults.standard.set(inspectorWidth, forKey: Keys.inspectorWidth) }
    }

    var panelVisibilityToken: String {
        "\(showAxisTree)-\(axisTreeCollapsed)-\(showInstances)-\(showInspector)-\(inspectorAutoHide)-\(inspectorPinnedOpen)"
    }

    init() {
        showAxisTree = Self.storedBool(forKey: Keys.axisTree, default: true)
        showInstances = Self.storedBool(forKey: Keys.instances, default: true)
        showInspector = Self.storedBool(forKey: Keys.inspector, default: true)
        axisTreeCollapsed = Self.storedBool(forKey: Keys.axisTreeCollapsed, default: false)
        inspectorAutoHide = Self.storedBool(forKey: Keys.inspectorAutoHide, default: true)
        axisTreeWidth = Self.storedCGFloat(forKey: Keys.axisTreeWidth, default: StudioPanelMetrics.axisTreeDefault)
        inspectorWidth = Self.storedCGFloat(forKey: Keys.inspectorWidth, default: StudioPanelMetrics.inspectorDefault)
    }

    func axisTreeOccupiedWidth() -> CGFloat {
        guard showAxisTree else { return 0 }
        return axisTreeCollapsed ? StudioPanelMetrics.axisTreeRailWidth : axisTreeWidth
    }

    func isInspectorPresented(inspectorHasSelection: Bool) -> Bool {
        guard showInspector else { return false }
        if !inspectorAutoHide { return true }
        return inspectorPinnedOpen || inspectorHasSelection
    }

    func inspectorOccupiedWidth(inspectorHasSelection: Bool) -> CGFloat {
        isInspectorPresented(inspectorHasSelection: inspectorHasSelection) ? inspectorWidth : 0
    }

    func userOpenedInspector() {
        inspectorPinnedOpen = true
    }

    private enum Keys {
        static let axisTree = "studio.showAxisTree"
        static let instances = "studio.showInstances"
        static let inspector = "studio.showInspector"
        static let axisTreeCollapsed = "studio.axisTreeCollapsed"
        static let inspectorAutoHide = "studio.inspectorAutoHide"
        static let axisTreeWidth = "studio.axisTreeWidth"
        static let inspectorWidth = "studio.inspectorWidth"
    }

    private static func storedCGFloat(forKey key: String, default defaultValue: CGFloat) -> CGFloat {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }

    private static func storedBool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func ensureAtLeastOnePanelVisible() {
        guard !showAxisTree, !showInstances, !showInspector else { return }
        showInstances = true
    }
}
