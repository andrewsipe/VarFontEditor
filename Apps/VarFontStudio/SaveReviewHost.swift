import Foundation
import VarFontCore

/// Project/editor surface that Save Review / Export orchestration needs.
/// Implemented by `EditorViewModel`; owned logic lives on `SaveReviewStore`.
@MainActor
protocol SaveReviewHost: AnyObject {
    var activeProjectID: String? { get }
    var selectedFontID: String? { get }
    var canSave: Bool { get }
    var isBusy: Bool { get set }
    var busyProgress: Double? { get set }
    var busyStatus: String? { get set }
    var openProjects: [OpenProject] { get set }
    var project: ProjectDocument? { get set }
    var commitService: CommitService { get }
    var sourceBookmarks: [String: Data] { get set }

    func postStatusMessage(_ message: String, dismissAfter seconds: TimeInterval?)
    func openProject(for id: String) -> OpenProject?
    func font(forProjectID projectID: String, fontID: String) -> FontDocument?
    func selectedFont(forProjectID projectID: String) -> FontDocument?
    func instancePlan(forProjectID projectID: String, fontID: String?) -> InstancePlan?
    func fontBasename(for font: FontDocument) -> String
    func projectTabLabel(for openProject: OpenProject) -> String
    func registerSourceBookmark(url: URL, fontID: String)
    func publishOpenProjects()
    func refreshCanSave()
    func postSaveFailure(_ message: String)
}

extension SaveReviewHost {
    func postStatusMessage(_ message: String) {
        postStatusMessage(message, dismissAfter: nil)
    }

    func instancePlan(forProjectID projectID: String) -> InstancePlan? {
        instancePlan(forProjectID: projectID, fontID: nil)
    }

    func beginBusyWork(status: String, progress: Double? = 0) {
        isBusy = true
        busyStatus = status
        busyProgress = progress
    }

    func updateBusyWork(status: String? = nil, progress: Double? = nil) {
        if let status { busyStatus = status }
        if let progress { busyProgress = min(1, max(0, progress)) }
    }

    func endBusyWork() {
        isBusy = false
        busyStatus = nil
        busyProgress = nil
    }
}
