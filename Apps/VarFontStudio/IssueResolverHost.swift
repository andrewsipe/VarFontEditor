import Foundation
import VarFontCore

/// Editor surface needed by conflict / plan-issue orchestration on `IssueResolverStore`.
@MainActor
protocol IssueResolverHost: AnyObject {
    var selectedFont: FontDocument? { get }
    var instancePlan: InstancePlan? { get }
    var project: ProjectDocument? { get set }
    var selectedFontID: String? { get }
    var selectedAxisStopID: String? { get set }
    var canSave: Bool { get set }
    var inspectorFocus: InspectorFocusStore { get }

    func pushUndoSnapshot()
    func regeneratePlan()
}
