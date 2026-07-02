import Foundation

public enum ProjectImporter {
  public static func openFont(at url: URL) throws -> ProjectDocument {
    let analysis = try FontAnalysisReader.analyze(url: url)
    return newProject(from: analysis, sourceURL: url)
  }

  public static func newProject(from analysis: FontAnalysis, sourceURL: URL) -> ProjectDocument {
    let font = fontDocument(from: analysis, sourceURL: sourceURL, isMaster: true, masterFontID: nil)
    let familyLabel = analysis.source.familyName.isEmpty
      ? sourceURL.deletingPathExtension().lastPathComponent
      : analysis.source.familyName

    let axisOrder = analysis.inferred.namingOrderSuggested
    return ProjectDocument(
      schemaVersion: 1,
      created: Date(),
      modified: Date(),
      familyLabel: familyLabel,
      naming: NamingPolicy(
        order: NamingPolicy.orderWithDefaultClarifiers(axisOrder: axisOrder),
        inferredOrder: axisOrder,
        elidedFallback: analysis.nameAudit.elidedFallbackName ?? "Regular"
      ),
      template: ProjectTemplate(syncRoles: true, axes: []),
      fonts: [font]
    )
  }

  public static func addFont(_ analysis: FontAnalysis, sourceURL: URL, to project: inout ProjectDocument) {
    let masterID = project.fonts.first { $0.fileRole?.kind == .master }?.id ?? project.fonts.first?.id
    let font = fontDocument(
      from: analysis,
      sourceURL: sourceURL,
      isMaster: project.fonts.isEmpty,
      masterFontID: masterID
    )
    project.fonts.append(font)
    if project.fonts.count > 1 {
      project.naming.order = NamingPolicy.orderWithDefaultClarifiers(axisOrder: project.naming.order)
    }
    project.modified = Date()
  }

  // MARK: - Private

  public static func axisDefinition(from axis: FontAnalysis.AnalyzedAxis) -> AxisDefinition {
    let isDesignRecordOnly = axis.roleInferred == .designRecordOnly
    var definition = AxisDefinition(
      tag: axis.tag,
      displayName: axis.displayName,
      min: isDesignRecordOnly ? nil : axis.min,
      default: isDesignRecordOnly ? nil : axis.default,
      max: isDesignRecordOnly ? nil : axis.max,
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
    let inferredMapping = AxisReferenceMapping.inferKind(for: definition)
    definition.referenceMappingInferred = inferredMapping
    definition.referenceMapping = inferredMapping
    definition.referenceAnchors = AxisReferenceMapping.inferAnchors(for: definition)
    if !AxisLadderAlignment.supportsAlignment(definition.tag) {
      definition.referenceMapping = .identity
      definition.referenceMappingInferred = .identity
      definition.referenceAnchors = []
    }
    return definition
  }

  private static func fontDocument(
    from analysis: FontAnalysis,
    sourceURL: URL,
    isMaster: Bool,
    masterFontID: String?
  ) -> FontDocument {
    let axes = analysis.axes.map { axisDefinition(from: $0) }

  let placeholder = FontDocument(
      id: UUID().uuidString,
      sourcePath: sourceURL.path,
      dirty: false,
      axes: axes
    )
    let inferred = FileClarifierInference.infer(
      sourceURL: sourceURL,
      analysis: analysis,
      font: placeholder
    )

    let fileRole: FileRole
    if isMaster {
      fileRole = .master()
    } else {
      fileRole = .variant(
        masterFontID: masterFontID ?? "",
        clarifiers: inferred.clarifiers,
        elidedFallbackOverride: inferred.elidedFallbackOverride
      )
    }

    return FontDocument(
      id: placeholder.id,
      sourcePath: sourceURL.path,
      outputPath: nil,
      analysisSnapshotID: nil,
      dirty: false,
      fileRole: fileRole,
      axes: axes,
      options: CommitOptions(familyPSPrefix: analysis.source.familyPSPrefix),
      includedInstanceKeys: [],
      excludedInstanceKeys: [],
      overrides: InstanceOverrides(),
      fileStatRegistration: RegistrationAxisSupport.inferFileStatRegistration(axes: axes)
    )
  }

  private static func resolvedStopValue(
    _ stop: FontAnalysis.StatValueSnapshot,
    axis: FontAnalysis.AnalyzedAxis
  ) -> Double {
    let raw: Double
    if let value = stop.value { raw = value }
    else if let nominal = stop.nominal { raw = nominal }
    else if axis.roleInferred == .designRecordOnly { raw = 0 }
    else { raw = axis.default }
    return AxisCoordinateFormat.canonical(raw)
  }
}
