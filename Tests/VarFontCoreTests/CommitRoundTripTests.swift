import XCTest
@testable import VarFontCore

final class CommitRoundTripTests: XCTestCase {
    // MARK: - Helpers

    private func commitService() throws -> CommitService {
        try LiveFontFixture.makeCommitService()
    }

    private func playfairProject() throws -> ProjectDocument {
        let path = try LiveFontFixture.requirePlayfairRoman()
        return try ProjectImporter.openFont(at: URL(fileURLWithPath: path))
    }

    private func playfairFontID(in project: ProjectDocument) throws -> String {
        try XCTUnwrap(project.fonts.first?.id)
    }

    private func makeWriteRequest(
        project: ProjectDocument,
        font: FontDocument,
        plan: InstancePlan,
        outputURL: URL
    ) -> CommitRequest {
        var request = CommitRequestBuilder.make(
            font: font,
            naming: project.naming,
            plan: plan,
            outputPath: outputURL.path,
            dryRun: false
        )
        request.sourcePath = font.sourcePath
        return request
    }

    private func fvarInstanceCount(at path: String) throws -> Int {
        let analysis = try FontAnalysisReader.analyzeForCommitDiff(url: URL(fileURLWithPath: path))
        if let total = analysis.instancesExistingMeta?.total {
            return total
        }
        return analysis.instancesExisting.count
    }

    // MARK: - Baseline round-trip

    func testPlayfairRomanWriteRoundTrip() async throws {
        let service = try commitService()
        let project = try playfairProject()
        let fontID = try playfairFontID(in: project)
        let font = try XCTUnwrap(project.fonts.first)
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: fontID))
        let expectedIncluded = plan.formula.totalIncluded

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayfairRoman-roundtrip-\(UUID().uuidString).woff2")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let request = makeWriteRequest(
            project: project,
            font: font,
            plan: plan,
            outputURL: outputURL
        )
        let result = try await service.commit(request)
        XCTAssertTrue(result.ok, result.errors.first?.message ?? "commit failed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let afterCount = try fvarInstanceCount(at: outputURL.path)
        XCTAssertEqual(afterCount, expectedIncluded)
        XCTAssertEqual(result.summary?.instancesWritten, expectedIncluded)

        let reanalysis = try FontAnalysisReader.analyzeForCommitDiff(url: outputURL)
        XCTAssertEqual(reanalysis.instancesExistingMeta?.total ?? reanalysis.instancesExisting.count, expectedIncluded)
        if let sampleName = plan.instances.first?.composedName {
            let writtenNames = Set(reanalysis.instancesExisting.map(\.composedName))
            XCTAssertTrue(writtenNames.contains(sampleName), "Expected \(sampleName) in written fvar")
        }

        let reimport = try ProjectImporter.openFont(at: outputURL)
        let reimportFontID = try XCTUnwrap(reimport.fonts.first?.id)
        let reimportPlan = try XCTUnwrap(InstancePlanner.plan(project: reimport, fontID: reimportFontID))
        XCTAssertEqual(reimportPlan.formula.totalGenerated, expectedIncluded)
        XCTAssertEqual(reimportPlan.formula.totalIncluded, expectedIncluded)
    }

    // MARK: - Edit matrix

    func testExcludeInstancesRoundTrip() async throws {
        let service = try commitService()
        var project = try playfairProject()
        let fontID = try playfairFontID(in: project)
        let fontIndex = 0
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: fontID))
        let targetKey = try XCTUnwrap(plan.instances.first { $0.included }?.key)
        project.fonts[fontIndex].excludedInstanceKeys = [targetKey]

        let prunedPlan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: fontID))
        let expected = prunedPlan.formula.totalIncluded
        XCTAssertEqual(expected, plan.formula.totalIncluded - 1)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayfairRoman-exclude-\(UUID().uuidString).woff2")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let request = makeWriteRequest(
            project: project,
            font: project.fonts[fontIndex],
            plan: prunedPlan,
            outputURL: outputURL
        )
        XCTAssertFalse(request.includedInstanceKeys.isEmpty)

        let result = try await service.commit(request)
        XCTAssertTrue(result.ok, result.errors.first?.message ?? "commit failed")
        XCTAssertEqual(try fvarInstanceCount(at: outputURL.path), expected)
    }

    func testRenameStopRoundTrip() async throws {
        let service = try commitService()
        var project = try playfairProject()
        let fontID = try playfairFontID(in: project)
        let fontIndex = 0
        guard let wghtIndex = project.fonts[fontIndex].axes.firstIndex(where: { $0.tag == "wght" }),
              let boldIndex = project.fonts[fontIndex].axes[wghtIndex].values.firstIndex(where: { $0.value == 700 })
        else {
            XCTFail("Expected wght axis with 700 stop")
            return
        }
        project.fonts[fontIndex].axes[wghtIndex].values[boldIndex].name = "Heavy"

        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: fontID))
        let heavyInstance = try XCTUnwrap(plan.instances.first { $0.coords["wght"] == 700 })
        XCTAssertTrue(heavyInstance.composedName.contains("Heavy"))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayfairRoman-rename-\(UUID().uuidString).woff2")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let request = makeWriteRequest(
            project: project,
            font: project.fonts[fontIndex],
            plan: plan,
            outputURL: outputURL
        )
        let result = try await service.commit(request)
        XCTAssertTrue(result.ok, result.errors.first?.message ?? "commit failed")

        let reanalysis = try FontAnalysisReader.analyzeForCommitDiff(url: outputURL)
        let boldInstances = reanalysis.instancesExisting.filter { ($0.coords["wght"] ?? 0) == 700 }
        XCTAssertFalse(boldInstances.isEmpty)
        XCTAssertTrue(
            boldInstances.contains { $0.composedName.contains("Heavy") },
            "fvar instances at wght=700 should use renamed stop; got: \(boldInstances.map(\.composedName))"
        )
    }

    func testRegistrationRoundTrip() async throws {
        let service = try commitService()
        var project = try playfairProject()
        let fontID = try playfairFontID(in: project)
        let fontIndex = 0
        project.fonts[fontIndex].fileStatRegistration = ["ital": 0]

        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: fontID))
        XCTAssertFalse(plan.instances.isEmpty)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayfairRoman-registration-\(UUID().uuidString).woff2")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let request = makeWriteRequest(
            project: project,
            font: project.fonts[fontIndex],
            plan: plan,
            outputURL: outputURL
        )
        let result = try await service.commit(request)
        XCTAssertTrue(result.ok, result.errors.first?.message ?? "commit failed")
        XCTAssertGreaterThan(try fvarInstanceCount(at: outputURL.path), 0)
    }

    func testClarifierAndPSPrefixInCommitRequest() throws {
        var project = try playfairProject()
        let fontID = try playfairFontID(in: project)
        project.fonts[0].fileRole = FileRole.variant(
            masterFontID: fontID,
            clarifiers: [FileClarifier(category: .width, label: "Condensed")]
        )
        project.fonts[0].options.familyPSPrefix = "PlayfairVF"

        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: fontID))
        let request = CommitRequestBuilder.make(
            font: project.fonts[0],
            naming: project.naming,
            plan: plan,
            outputPath: "/tmp/out.woff2",
            dryRun: true
        )
        XCTAssertEqual(request.options.familyPSPrefix, "PlayfairVF")
        XCTAssertEqual(request.fileRole?.clarifiers.first?.label, "Condensed")
    }

    func testRobotoFlexWriteRoundTrip() async throws {
        let path = try LiveFontFixture.requireRobotoFlex()
        let service = try commitService()
        let project = try ProjectImporter.openFont(at: URL(fileURLWithPath: path))
        let font = try XCTUnwrap(project.fonts.first)
        let plan = try XCTUnwrap(InstancePlanner.plan(project: project, fontID: font.id))
        XCTAssertEqual(plan.formula.parts, [9, 1])

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RobotoFlex-roundtrip-\(UUID().uuidString).ttf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let request = makeWriteRequest(
            project: project,
            font: font,
            plan: plan,
            outputURL: outputURL
        )
        let result = try await service.commit(request)
        XCTAssertTrue(result.ok, result.errors.first?.message ?? "commit failed")
        XCTAssertEqual(try fvarInstanceCount(at: outputURL.path), plan.formula.totalIncluded)
    }
}
