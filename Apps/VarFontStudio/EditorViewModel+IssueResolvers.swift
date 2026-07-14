import Foundation
import VarFontCore

extension EditorViewModel {
    // MARK: - Conflict / plan-issue (facades → IssueResolverStore)

    func instanceAffectedByUnresolvedConflict(_ instance: PlannedInstance) -> Bool {
        issueResolvers.instanceAffectedByUnresolvedConflict(instance)
    }

    func primaryConflictAxis(for instance: PlannedInstance) -> AxisConflictBundle? {
        issueResolvers.primaryConflictAxis(for: instance)
    }

    var axisConflictBundles: [AxisConflictBundle] { issueResolvers.axisConflictBundles }

    var unresolvedAxisConflictCount: Int { issueResolvers.unresolvedAxisConflictCount }

    func bundle(for axisTag: String) -> AxisConflictBundle? {
        issueResolvers.bundle(for: axisTag)
    }

    func presentConflictResolver(for axisTag: String) {
        issueResolvers.presentConflictResolver(for: axisTag)
    }

    func presentConflictResolver(bundle: AxisConflictBundle) {
        issueResolvers.presentConflictResolver(bundle: bundle)
    }

    func presentFirstConflictResolver() {
        issueResolvers.presentFirstConflictResolver()
    }

    func dismissConflictResolver() {
        issueResolvers.dismissConflictResolver()
    }

    func reviewQueue() -> [AxisTreeReviewItem] {
        issueResolvers.reviewQueue()
    }

    var reviewIssueCount: Int { issueResolvers.reviewIssueCount }

    func informationalPlanWarnings() -> [PlanWarning] {
        issueResolvers.informationalPlanWarnings()
    }

    func startReviewSession(jumpingTo warning: PlanWarning? = nil) {
        issueResolvers.startReviewSession(jumpingTo: warning)
    }

    func startAxisReviewSession(on axisTag: String) {
        issueResolvers.startAxisReviewSession(on: axisTag)
    }

    func continueReviewSession() {
        issueResolvers.continueReviewSession()
    }

    func advanceReviewSession() {
        issueResolvers.advanceReviewSession()
    }

    func endReviewSession() {
        issueResolvers.endReviewSession()
    }

    func resolvablePlanWarnings(for axisTag: String) -> [PlanWarning] {
        issueResolvers.resolvablePlanWarnings(for: axisTag)
    }

    func planIssueProposals(for warning: PlanWarning) -> [PlanIssueProposal] {
        issueResolvers.planIssueProposals(for: warning)
    }

    func applyPlanIssueFix(_ action: PlanIssueAction, andContinue: Bool = false) {
        issueResolvers.applyPlanIssueFix(action, andContinue: andContinue)
    }

    func presentPlanIssueResolver(for warning: PlanWarning) {
        issueResolvers.presentPlanIssueResolver(for: warning)
    }

    func presentFirstResolvablePlanIssue(on axisTag: String) {
        issueResolvers.presentFirstResolvablePlanIssue(on: axisTag)
    }

    func dismissPlanIssueResolver() {
        issueResolvers.dismissPlanIssueResolver()
    }

    func applyConflictFix(_ action: ConflictFixAction, axisTag: String, andContinue: Bool = false) {
        issueResolvers.applyConflictFix(action, axisTag: axisTag, andContinue: andContinue)
    }

    // MARK: - Naming / compound helpers (remain on editor)

    func setElidedFallback(_ value: String) {
        guard var project else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Regular" : trimmed
        guard resolved != project.naming.elidedFallback else { return }
        pushUndoSnapshot()
        project.naming.elidedFallback = resolved
        project.modified = Date()
        self.project = project
        regeneratePlan()
    }
    func updateCompoundStatName(id: String, name: String) {
        mutateSelectedFont { font in
            guard let index = font.compoundStatValues.firstIndex(where: { $0.id == id }) else { return }
            font.compoundStatValues[index].name = name
        }
    }
    func updateCompoundStatElidable(id: String, elidable: Bool) {
        mutateSelectedFont { font in
            guard let index = font.compoundStatValues.firstIndex(where: { $0.id == id }) else { return }
            font.compoundStatValues[index].elidable = elidable
        }
    }
    func updateCompoundStatCoordinate(id: String, tag: String, value: Double) {
        mutateSelectedFont { font in
            guard let index = font.compoundStatValues.firstIndex(where: { $0.id == id }) else { return }
            font.compoundStatValues[index].coords[tag] = value
            CompoundStatCoordinateSync.syncIndicesAndValues(
                compound: &font.compoundStatValues[index],
                designAxisOrder: font.axes
            )
        }
    }
    func axisStop(for instance: PlannedInstance, tag: String) -> (axisTag: String, stopID: String)? {
        guard let font = selectedFont,
              let coord = instance.coords[tag],
              let axis = font.axes.first(where: { $0.tag == tag }),
              let stop = axis.values.first(where: { AxisCoordinate.valuesEqual($0.value, coord) }) else {
            return nil
        }
        return (tag, stop.id)
    }
}
