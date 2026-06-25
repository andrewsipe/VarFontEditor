import Foundation

public enum ProjectImporter {
  public static func openFont(at url: URL) throws -> ProjectDocument {
    let analysis = try FontAnalysisReader.analyze(url: url)
    return newProject(from: analysis, sourceURL: url)
  }

  public static func newProject(from analysis: FontAnalysis, sourceURL: URL) -> ProjectDocument {
    let font = fontDocument(from: analysis, sourceURL: sourceURL)
    let familyLabel = analysis.source.familyName.isEmpty
      ? sourceURL.deletingPathExtension().lastPathComponent
      : analysis.source.familyName

    return ProjectDocument(
      schemaVersion: 1,
      created: Date(),
      modified: Date(),
      familyLabel: familyLabel,
      naming: NamingPolicy(
        order: analysis.inferred.namingOrderSuggested,
        inferredOrder: analysis.inferred.namingOrderSuggested,
        elidedFallback: analysis.nameAudit.elidedFallbackName ?? "Regular"
      ),
      template: ProjectTemplate(syncRoles: true, axes: []),
      fonts: [font]
    )
  }

  public static func addFont(_ analysis: FontAnalysis, sourceURL: URL, to project: inout ProjectDocument) {
    let font = fontDocument(from: analysis, sourceURL: sourceURL)
    project.fonts.append(font)
    project.modified = Date()
  }

  // MARK: - Private

  private static func fontDocument(from analysis: FontAnalysis, sourceURL: URL) -> FontDocument {
    let axes = analysis.axes.map { axis in
      AxisDefinition(
        tag: axis.tag,
        displayName: axis.displayName,
        min: axis.min,
        default: axis.default,
        max: axis.max,
        role: axis.roleInferred,
        roleInferred: axis.roleInferred,
        values: axis.valuesExisting.map { stop in
          AxisValue(
            id: "\(axis.tag)-\(UUID().uuidString.prefix(8))",
            value: resolvedStopValue(stop, axis: axis),
            name: stop.name,
            elidable: stop.elidable ?? false,
            statFormat: stop.format ?? 1,
            rangeMin: stop.rangeMin,
            rangeMax: stop.rangeMax,
            linkedValue: stop.linkedValue
          )
        }
      )
    }

    return FontDocument(
      id: UUID().uuidString,
      sourcePath: sourceURL.path,
      outputPath: nil,
      analysisSnapshotID: nil,
      dirty: false,
      axes: axes,
      options: CommitOptions(),
      includedInstanceKeys: [],
      excludedInstanceKeys: [],
      overrides: InstanceOverrides()
    )
  }

  private static func resolvedStopValue(
    _ stop: FontAnalysis.StatValueSnapshot,
    axis: FontAnalysis.AnalyzedAxis
  ) -> Double {
    if let value = stop.value { return value }
    if let nominal = stop.nominal { return nominal }
    return axis.default
  }
}
