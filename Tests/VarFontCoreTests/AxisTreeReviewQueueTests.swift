import XCTest
@testable import VarFontCore

final class AxisTreeReviewQueueTests: XCTestCase {
    private func bundles(from plan: InstancePlan, axes: [AxisDefinition]) -> [AxisConflictBundle] {
        AxisConflictBundler.bundles(
            warnings: plan.warnings,
            axes: axes,
            namingOrder: axes.map(\.tag)
        )
    }

    private func queue(
        plan: InstancePlan,
        axes: [AxisDefinition],
        namingOrder: [String]? = nil
    ) -> [AxisTreeReviewItem] {
        let order = namingOrder ?? axes.map(\.tag)
        return AxisTreeReviewQueue.build(
            warnings: plan.warnings,
            conflictBundles: bundles(from: plan, axes: axes),
            namingOrder: order
        )
    }

    private func firstCode(_ item: AxisTreeReviewItem) -> String {
        switch item {
        case let .planIssue(warning):
            return warning.code
        case let .axisConflict(bundle):
            return bundle.kind.rawValue
        }
    }

    func testNouveauLEDOrphanBeforeElidable() {
        let axes = [
            AxisDefinition(
                tag: "wght",
                role: .instance,
                values: (0...4).map { i in
                    AxisValue(id: "w\(i)", value: Double(i * 250), name: "Regular", elidable: true)
                }
            ),
            AxisDefinition(
                tag: "FLOR",
                role: .instance,
                values: (0...5).map { i in
                    AxisValue(id: "f\(i)", value: Double(i * 100), name: "Regular", elidable: true)
                }
            ),
            AxisDefinition(
                tag: "ital",
                role: .instance,
                values: [
                    AxisValue(id: "i0", value: 0, name: "Roman", elidable: true, statFormat: 3, linkedValue: 99),
                ]
            ),
        ]
        let font = FontDocument(id: "led", sourcePath: "/tmp/NouveauLED.ttf", axes: axes)
        let plan = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wght", "FLOR", "ital"]))

        let items = queue(plan: plan, axes: axes)
        let first = items.first
        guard case let .planIssue(warning) = first else {
            XCTFail("Expected first issue to be orphan F3 link, got \(String(describing: first))")
            return
        }
        XCTAssertEqual(warning.code, "orphan_stat_link")
        XCTAssertEqual(warning.axis, "ital")

        let elidableIndex = items.firstIndex { item in
            if case let .planIssue(w) = item { return w.code == "multiple_elidable" }
            return false
        }
        XCTAssertNotNil(elidableIndex)
        XCTAssertGreaterThan(elidableIndex!, 0)
    }

    func testNouveauLEDStructuralBeforeComposedDuplicates() {
        let axes = [
            AxisDefinition(
                tag: "wght",
                role: .instance,
                values: (0...4).map { i in
                    AxisValue(id: "w\(i)", value: Double(i * 250), name: "Regular", elidable: true)
                }
            ),
            AxisDefinition(
                tag: "FLOR",
                role: .instance,
                values: (0...5).map { i in
                    AxisValue(id: "f\(i)", value: Double(i * 100), name: "Regular", elidable: true)
                }
            ),
            AxisDefinition(
                tag: "ital",
                role: .instance,
                values: [
                    AxisValue(id: "i0", value: 0, name: "Roman", elidable: true, statFormat: 3, linkedValue: 1),
                ]
            ),
        ]
        let font = FontDocument(id: "led", sourcePath: "/tmp/NouveauLED.ttf", axes: axes)
        let plan = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wght", "FLOR", "ital"]))

        let items = queue(plan: plan, axes: axes)
        XCTAssertFalse(items.isEmpty)

        let structuralIndex = items.firstIndex { item in
            if case let .planIssue(w) = item { return w.code == "multiple_elidable" }
            return false
        }
        let composedIndex = items.firstIndex { item in
            if case let .planIssue(w) = item { return w.code == "duplicate_composed_name" }
            return false
        }
        XCTAssertNotNil(structuralIndex)
        XCTAssertNotNil(composedIndex)
        XCTAssertLessThan(structuralIndex!, composedIndex!)
    }

    func testReflexValueConflictBeforeNamingQoL() {
        let axes = [
            AxisDefinition(
                tag: "wdth",
                role: .instance,
                values: [
                    AxisValue(id: "w1", value: 50, name: "Condensed", elidable: false),
                    AxisValue(id: "w2", value: 100, name: "Regular", elidable: true),
                    AxisValue(id: "w3", value: 150, name: "Expanded", elidable: false),
                    AxisValue(id: "w4", value: 100, name: "Bold", elidable: false),
                    AxisValue(id: "w5", value: 100, name: "Black", elidable: false),
                ]
            ),
            AxisDefinition(
                tag: "wght",
                role: .instance,
                values: [
                    AxisValue(id: "g1", value: 400, name: "Regular", elidable: true),
                    AxisValue(id: "g2", value: 700, name: "Bold", elidable: false),
                ]
            ),
            AxisDefinition(
                tag: "ital",
                role: .instance,
                values: [
                    AxisValue(id: "i1", value: 0, name: "Regular", elidable: true),
                    AxisValue(id: "i2", value: 9, name: "Italic", elidable: false),
                ]
            ),
        ]
        let font = FontDocument(id: "reflex", sourcePath: "/tmp/Reflex.ttf", axes: axes)
        let plan = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wdth", "wght", "ital"]))

        let items = queue(plan: plan, axes: axes)
        let conflictIndex = items.firstIndex {
            if case .axisConflict = $0 { return true }
            return false
        }
        let neutralIndex = items.firstIndex {
            if case let .planIssue(w) = $0 { return w.code == "axis_neutral_mismatch" }
            return false
        }
        XCTAssertNotNil(conflictIndex)
        XCTAssertNotNil(neutralIndex)
        XCTAssertLessThan(conflictIndex!, neutralIndex!)
    }

    func testPlayfairOrphanBeforeNeutralMismatch() {
        let axes = [
            AxisDefinition(
                tag: "wdth",
                role: .instance,
                values: [
                    AxisValue(id: "w1", value: 100, name: "Normal", elidable: true),
                ]
            ),
            AxisDefinition(
                tag: "wght",
                role: .instance,
                values: [
                    AxisValue(id: "g1", value: 400, name: "Normal", elidable: true),
                ]
            ),
            AxisDefinition(
                tag: "ital",
                role: .instance,
                values: [
                    AxisValue(id: "i1", value: 0, name: "Roman", elidable: true, statFormat: 3, linkedValue: 99),
                ]
            ),
        ]
        let font = FontDocument(id: "playfair", sourcePath: "/tmp/Playfair.ttf", axes: axes)
        let plan = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wdth", "wght", "ital"]))

        let items = queue(plan: plan, axes: axes)
        guard items.count >= 2 else {
            XCTFail("Expected orphan and neutral mismatch issues")
            return
        }
        let firstCodes = items.prefix(2).map(firstCode)
        XCTAssertTrue(firstCodes.contains("orphan_stat_link") || firstCodes.contains("ital_value_name_mismatch"))
        XCTAssertTrue(items.contains { item in
            if case let .planIssue(w) = item { return w.code == "axis_neutral_mismatch" }
            return false
        })
    }

    func testConflictWarningsNotDuplicatedAsPlanIssues() {
        let axes = [
            AxisDefinition(
                tag: "wdth",
                role: .instance,
                values: [
                    AxisValue(id: "w1", value: 100, name: "A", elidable: true),
                    AxisValue(id: "w2", value: 100, name: "B", elidable: false),
                ]
            ),
        ]
        let font = FontDocument(id: "dup", sourcePath: "/tmp/dup.ttf", axes: axes)
        let plan = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wdth"]))

        let items = queue(plan: plan, axes: axes)
        let planConflictCodes = items.compactMap { item -> String? in
            guard case let .planIssue(w) = item else { return nil }
            return w.code
        }
        XCTAssertFalse(planConflictCodes.contains("duplicate_stop_value"))
        XCTAssertFalse(planConflictCodes.contains("duplicate_stop_name"))
        XCTAssertTrue(items.contains { if case .axisConflict = $0 { return true }; return false })
    }

    func testEmptyInstanceAxisEnqueuedWhenResolvable() {
        let axes = [
            AxisDefinition(tag: "wdth", role: .instance, values: []),
        ]
        let font = FontDocument(id: "empty", sourcePath: "/tmp/empty.ttf", axes: axes)
        let plan = InstancePlanner.plan(font: font, naming: NamingPolicy(order: ["wdth"]))
        let items = queue(plan: plan, axes: axes)
        XCTAssertTrue(items.contains { item in
            if case let .planIssue(w) = item { return w.code == "empty_instance_axis" }
            return false
        })
    }
}
