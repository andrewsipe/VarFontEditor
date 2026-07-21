import Foundation

public enum SaveReviewPresentationBuilder {
  public static func build(
    analysis: FontAnalysis,
    font: FontDocument,
    plan: InstancePlan,
    report: CommitDiffReport,
    diff: CommitDiff?,
    naming: NamingPolicy
  ) -> SaveReviewPresentation {
    let namingOrder = NamingPolicy.mergedOrder(
      projectOrder: naming.order,
      axisTags: font.axes.map(\.tag)
    )
    let statTab = buildStatTab(
      analysis: analysis,
      font: font,
      report: report,
      diff: diff
    )
    let fvarTab = buildFvarTab(
      analysis: analysis,
      font: font,
      plan: plan,
      report: report,
      diff: diff,
      namingOrder: namingOrder
    )
    let nameTab = buildNameTab(
      analysis: analysis,
      font: font,
      plan: plan,
      report: report,
      diff: diff
    )
    return SaveReviewPresentation(tabs: [statTab, fvarTab, nameTab])
  }

  // MARK: - STAT

  private static func buildStatTab(
    analysis: FontAnalysis,
    font: FontDocument,
    report: CommitDiffReport,
    diff: CommitDiff?
  ) -> SaveReviewTabPresentation {
    let designTags = statDesignTags(font: font, analysis: analysis)
    var sections: [SaveReviewSectionPresentation] = []

    if !designTags.isEmpty {
      let axisRows = designTags.enumerated().map { index, tag in
        let displayName = font.axes.first(where: { $0.tag == tag })?.displayName
        return makeSyntheticAxisRow(
          tag: tag,
          displayName: displayName,
          index: index,
          font: font,
          diff: diff
        )
      }
      sections.append(SaveReviewSectionPresentation(title: "Axis records", rows: axisRows))
    }

    let beforeFormatByKey = Dictionary(
      uniqueKeysWithValues: analysis.statValues.map {
        (statValueKey(tag: $0.tag, value: $0.value ?? $0.nominal ?? 0), $0.format)
      }
    )

    for tag in font.axes.map(\.tag) {
      let axis = font.axes.first(where: { $0.tag == tag })
      let isNamingAxis = axis?.isDesignRecordOnly == true
      let axisStatRows = report.statRows
        .filter { $0.tag == tag }
        .sorted { $0.value < $1.value }
      guard !axisStatRows.isEmpty else { continue }
      let rows = axisStatRows.map { row -> SaveReviewRowPresentation in
        let key = statValueKey(tag: row.tag, value: row.value)
        let beforeFormat = beforeFormatByKey[key]
        let category = SaveReviewDisplayCategoryMapper.category(for: row)
        let afterValue = SaveReviewRowFormatter.statAfterValue(row)
        let wasLine = SaveReviewRowFormatter.statWasLine(row: row, beforeFormat: beforeFormat)
        let fieldTitle = SaveReviewRowFormatter.statFieldTitle(tag: row.tag, value: row.value)
        let fieldSubtitle = SaveReviewRowFormatter.statFieldSubtitle(
          row: row,
          beforeFormat: beforeFormat,
          namingAxis: isNamingAxis
        )
        let roleLabel = isNamingAxis
          ? "naming_axis"
          : SaveReviewRowFormatter.statMachineRole(format: row.afterStatFormat)
        let noteLine = isNamingAxis ? namingAxisRegistrationNote(font: font, tag: tag) : nil
        return SaveReviewRowPresentation(
          id: "stat:\(key)",
          nameID: row.afterNameID,
          fieldTitle: fieldTitle,
          fieldSubtitle: fieldSubtitle,
          afterValue: afterValue,
          wasLine: wasLine,
          noteLine: noteLine,
          roleLabel: roleLabel,
          category: category,
          searchText: SaveReviewRowFormatter.searchText(
            nameID: row.afterNameID,
            fieldTitle: fieldTitle,
            fieldSubtitle: fieldSubtitle,
            afterValue: afterValue,
            wasLine: wasLine,
            noteLine: noteLine,
            roleLabel: roleLabel
          )
        )
      }
      let displayName = font.axes.first(where: { $0.tag == tag })?.displayName ?? tag
      sections.append(SaveReviewSectionPresentation(title: displayName, rows: rows))
    }

    if let elidedRow = buildElidedFallbackStatRow(analysis: analysis, diff: diff) {
      sections.append(SaveReviewSectionPresentation(title: "Elidable fallback", rows: [elidedRow]))
    }

    return tabPresentation(
      id: .stat,
      label: SaveReviewTableTab.stat.label,
      headline: "STAT axis values and elidable fallback",
      sections: sections
    )
  }

  private static func buildElidedFallbackStatRow(
    analysis: FontAnalysis,
    diff: CommitDiff?
  ) -> SaveReviewRowPresentation? {
    let beforeName = analysis.nameAudit.elidedFallbackName
    let afterName = diff?.elidedFallbackName
    guard beforeName != nil || afterName != nil else { return nil }
    let category: SaveReviewDisplayCategory
    if beforeName == afterName || (beforeName == nil && afterName != nil) {
      category = beforeName == afterName ? .same : .added
    } else if afterName == nil {
      category = .removed
    } else {
      category = .renamed
    }
    let fieldTitle = "Elidable fallback name"
    let fieldSubtitle = "Elidable fallback"
    let nameID = diff?.elidedFallbackID ?? analysis.nameAudit.elidedFallbackID
    let afterValue = afterName.map { SaveReviewRowFormatter.quoted($0) }
    let wasLine = category == .renamed ? beforeName.map { "was \(SaveReviewRowFormatter.quoted($0))" } : nil
    return SaveReviewRowPresentation(
      id: "stat:elided",
      nameID: nameID,
      fieldTitle: fieldTitle,
      fieldSubtitle: fieldSubtitle,
      afterValue: afterValue,
      wasLine: wasLine,
      noteLine: nil,
      roleLabel: nil,
      category: category,
      searchText: SaveReviewRowFormatter.searchText(
        nameID: nameID,
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: wasLine,
        noteLine: nil,
        roleLabel: nil
      )
    )
  }

  // MARK: - fvar

  private static func buildFvarTab(
    analysis: FontAnalysis,
    font: FontDocument,
    plan: InstancePlan,
    report: CommitDiffReport,
    diff: CommitDiff?,
    namingOrder: [String]
  ) -> SaveReviewTabPresentation {
    var sections: [SaveReviewSectionPresentation] = []

    // fvar axis records are not rewritten on save — list them in the source font's
    // fvar order with matching Axis[n] indices, not project/STAT tree order.
    let projectByTag = Dictionary(
      uniqueKeysWithValues: font.axes.filter(\.hasFvarScale).map { ($0.tag, $0) }
    )
    var seen = Set<String>()
    var orderedFvarTags: [String] = []
    for axis in analysis.axes where axis.roleInferred != .designRecordOnly {
      if seen.insert(axis.tag).inserted {
        orderedFvarTags.append(axis.tag)
      }
    }
    for axis in font.axes where axis.hasFvarScale {
      if seen.insert(axis.tag).inserted {
        orderedFvarTags.append(axis.tag)
      }
    }

    let sourceByTag = Dictionary(
      uniqueKeysWithValues: analysis.axes
        .filter { $0.roleInferred != .designRecordOnly }
        .map { ($0.tag, $0) }
    )

    let axisRows = orderedFvarTags.enumerated().compactMap { index, tag -> SaveReviewRowPresentation? in
      let project = projectByTag[tag]
      let source = sourceByTag[tag]
      let displayName = project?.displayName ?? source?.displayName
      let noteParts = fvarAxisNoteLines(axisTag: tag, analysis: analysis, font: font)
      let noteLine = noteParts.isEmpty
        ? SaveReviewRowFormatter.fvarProtectedNote
        : ([SaveReviewRowFormatter.fvarProtectedNote] + noteParts).joined(separator: " · ")
      let fieldTitle = SaveReviewRowFormatter.fvarAxisFieldTitle(displayName: displayName, tag: tag)
      let fieldSubtitle = SaveReviewRowFormatter.fvarAxisFieldSubtitle(index: index)
      // Scales shown are the source fvar values that remain on disk (not rewritten).
      let afterValue = SaveReviewRowFormatter.fvarAxisAfterValue(
        min: source?.min ?? project?.min,
        default: source?.default ?? project?.default,
        max: source?.max ?? project?.max
      )
      return SaveReviewRowPresentation(
        id: "fvar:axis:\(tag)",
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: nil,
        noteLine: noteLine,
        roleLabel: nil,
        category: .protected,
        searchText: SaveReviewRowFormatter.searchText(
          fieldTitle: fieldTitle,
          fieldSubtitle: fieldSubtitle,
          afterValue: afterValue,
          wasLine: nil,
          noteLine: noteLine,
          roleLabel: nil
        )
      )
    }
    if !axisRows.isEmpty {
      sections.append(
        SaveReviewSectionPresentation(title: "Axes (source fvar order)", rows: axisRows)
      )
    }

    let instanceRows = report.instanceRows.enumerated().flatMap { index, row in
      makeFvarInstanceRows(index: index, row: row, namingOrder: namingOrder, diff: diff)
    }
    sections.append(SaveReviewSectionPresentation(title: "Instances", rows: instanceRows))

    return tabPresentation(
      id: .fvar,
      label: SaveReviewTableTab.fvar.label,
      headline: "fvar instances (axis record order + scales are read-only)",
      sections: sections
    )
  }

  private static func fvarAxisNoteLines(
    axisTag: String,
    analysis: FontAnalysis,
    font: FontDocument
  ) -> [String] {
    var notes: [String] = []
    for divergence in FvarDesignSpaceAudit.divergences(analysis: analysis, font: font)
      where divergence.axisTag == axisTag
    {
      notes.append(
        "\(divergence.field) in this project (\(AxisCoordinateFormat.format(divergence.projectValue))) "
          + "differs from source (\(AxisCoordinateFormat.format(divergence.sourceValue)))"
      )
    }
    for message in OpenTypeAxisAudit.registeredDefaultMessages(analysis: analysis, font: font)
      where message.hasPrefix("\(axisTag) ")
    {
      notes.append(message)
    }
    return notes
  }

  // MARK: - name

  private static func buildNameTab(
    analysis: FontAnalysis,
    font: FontDocument,
    plan: InstancePlan,
    report: CommitDiffReport,
    diff: CommitDiff?
  ) -> SaveReviewTabPresentation {
    let nameByID = Dictionary(uniqueKeysWithValues: report.nameIDRows.map { ($0.id, $0) })
    let statNameIDToTagValue = statNameIDLookup(diff: diff)
    let otFeatureByNameID = otFeatureTagLookup(diff: diff)
    var consumedIDs = Set<Int>()
    var sections: [SaveReviewSectionPresentation] = []

    let windowsRows = windowsNamePatchRows(analysis: analysis, font: font, diff: diff)
    if !windowsRows.isEmpty {
      sections.append(
        SaveReviewSectionPresentation(title: "Windows name IDs (0–25) · 3/1/0x409", rows: windowsRows)
      )
    }

    var reflowedOTRows: [SaveReviewRowPresentation] = []
    let sequenced = diff?.nameRecordsSequenced ?? []
    for record in sequenced where record.role == "ot_feature_label" {
      guard let row = nameByID[record.id] else { continue }
      reflowedOTRows.append(
        makeNameRow(
          row,
          font: font,
          diff: diff,
          tagValue: nil,
          otFeatureTag: otFeatureByNameID[record.id],
          consumed: &consumedIDs
        )
      )
    }
    if !reflowedOTRows.isEmpty {
      sections.append(
        SaveReviewSectionPresentation(title: "OpenType feature labels", rows: reflowedOTRows)
      )
    }

    var axisDisplayRows: [SaveReviewRowPresentation] = []
    let designTags = statDesignTags(font: font, analysis: analysis)
    for tag in designTags {
      let displayName = font.axes.first(where: { $0.tag == tag })?.displayName
      guard let record = sequenced.first(where: { record in
        guard record.role == "axis_display_name" else { return false }
        if let displayName, record.string == displayName { return true }
        return record.string == tag
      }),
      let row = nameByID[record.id] else { continue }
      axisDisplayRows.append(
        makeNameRow(
          row,
          font: font,
          diff: diff,
          tagValue: nil,
          axisTag: tag,
          consumed: &consumedIDs
        )
      )
    }
    if !axisDisplayRows.isEmpty {
      sections.append(SaveReviewSectionPresentation(title: "Axis records", rows: axisDisplayRows))
    }

    for axis in font.axes {
      var axisRows: [SaveReviewRowPresentation] = []
      for stop in axis.values.sorted(by: { $0.value < $1.value }) {
        guard let nameID = diff?.statValuesPlanned.first(where: {
          $0.tag == axis.tag && AxisCoordinate.valuesEqual($0.value, stop.value)
        })?.nameID else { continue }
        guard let row = nameByID[nameID] else { continue }
        let tagValue = (axis.tag, stop.value)
        axisRows.append(makeNameRow(row, font: font, diff: diff, tagValue: tagValue, consumed: &consumedIDs))
      }
      if axisRows.isEmpty { continue }
      sections.append(
        SaveReviewSectionPresentation(title: axis.displayName ?? axis.tag, rows: axisRows)
      )
    }

    if let elidedID = diff?.elidedFallbackID ?? analysis.nameAudit.elidedFallbackID,
       let row = nameByID[elidedID]
    {
      sections.append(
        SaveReviewSectionPresentation(
          title: "Elidable fallback",
          rows: [makeNameRow(row, font: font, diff: diff, tagValue: nil, consumed: &consumedIDs)]
        )
      )
    }

    var instanceRows: [SaveReviewRowPresentation] = []
    for instance in plan.instances where instance.included {
      let subfamilyRow = report.nameIDRows.first {
        $0.afterString == instance.composedName && $0.afterRole == "instance_subfamily"
      }
      if let subfamilyRow {
        instanceRows.append(makeNameRow(subfamilyRow, font: font, diff: diff, tagValue: nil, consumed: &consumedIDs))
      }
      if let psName = diff?.instancesPlanned.first(where: { $0.composedName == instance.composedName })?
        .postscriptName,
        let psRow = report.nameIDRows.first(where: {
          $0.afterString == psName && $0.afterRole == "instance_postscript"
        })
      {
        instanceRows.append(makeNameRow(psRow, font: font, diff: diff, tagValue: nil, consumed: &consumedIDs))
      }
    }
    if !instanceRows.isEmpty {
      sections.append(SaveReviewSectionPresentation(title: "Instances", rows: instanceRows))
    }

    let protectedRows = report.nameIDRows
      .filter { $0.afterRole == "protected_ot_label" && !consumedIDs.contains($0.id) }
      .map { makeNameRow($0, font: font, diff: diff, tagValue: nil, consumed: &consumedIDs) }
    if !protectedRows.isEmpty {
      sections.append(
        SaveReviewSectionPresentation(title: "OpenType feature labels", rows: protectedRows)
      )
    }

    let removedRows = report.nameIDRows
      .filter { SaveReviewDisplayCategoryMapper.category(for: $0) == .removed && !$0.reflowSuppressed }
      .sorted { $0.id < $1.id }
      .map { makeNameRow($0, font: font, diff: diff, tagValue: statNameIDToTagValue[$0.id], consumed: &consumedIDs) }
    if !removedRows.isEmpty {
      sections.append(SaveReviewSectionPresentation(title: "Removed slots", rows: removedRows))
    }

    return tabPresentation(
      id: .name,
      label: SaveReviewTableTab.name.label,
      headline: "name table slots ≥256 in write order",
      sections: sections
    )
  }

  // MARK: - Row factories

  private static func makeFvarInstanceRows(
    index: Int,
    row: CommitDiffInstanceRow,
    namingOrder: [String],
    diff: CommitDiff?
  ) -> [SaveReviewRowPresentation] {
    let coordsSubtitle = SaveReviewRowFormatter.instanceSubtitle(
      coords: row.coords,
      namingOrder: namingOrder
    )
    let composedName = row.afterName ?? row.beforeName
    let planned = composedName.flatMap { name in
      diff?.instancesPlanned.first { $0.composedName == name }
    }
    var rows: [SaveReviewRowPresentation] = []

    let subfamilyCategory = SaveReviewDisplayCategoryMapper.category(for: row)
    let subfamilyTitle = "Instance \(index + 1)"
    let subfamilyAfter = SaveReviewRowFormatter.instanceAfterValue(row)
    let subfamilyWas = SaveReviewRowFormatter.instanceWasLine(row)
    rows.append(
      SaveReviewRowPresentation(
        id: "fvar:instance:\(row.key):subfamily",
        nameID: planned?.subfamilyNameID,
        fieldTitle: subfamilyTitle,
        fieldSubtitle: coordsSubtitle,
        afterValue: subfamilyAfter,
        wasLine: subfamilyWas,
        noteLine: nil,
        roleLabel: "subfamilyNameID",
        category: subfamilyCategory,
        searchText: SaveReviewRowFormatter.searchText(
          nameID: planned?.subfamilyNameID,
          fieldTitle: subfamilyTitle,
          fieldSubtitle: coordsSubtitle,
          afterValue: subfamilyAfter,
          wasLine: subfamilyWas,
          noteLine: nil,
          roleLabel: "subfamilyNameID"
        )
      )
    )

    if row.afterPostscriptName != nil || row.beforePostscriptName != nil {
      let psCategory = SaveReviewDisplayCategoryMapper.postscriptCategory(for: row)
      let psTitle = "Instance \(index + 1) PostScript"
      let psAfter = SaveReviewRowFormatter.instancePostscriptAfterValue(row)
      let psWas = SaveReviewRowFormatter.instancePostscriptWasLine(row)
      rows.append(
        SaveReviewRowPresentation(
          id: "fvar:instance:\(row.key):postscript",
          nameID: planned?.postscriptNameID,
          fieldTitle: psTitle,
          fieldSubtitle: coordsSubtitle,
          afterValue: psAfter,
          wasLine: psWas,
          noteLine: nil,
          roleLabel: "postscriptNameID",
          category: psCategory,
          searchText: SaveReviewRowFormatter.searchText(
            nameID: planned?.postscriptNameID,
            fieldTitle: psTitle,
            fieldSubtitle: coordsSubtitle,
            afterValue: psAfter,
            wasLine: psWas,
            noteLine: nil,
            roleLabel: "postscriptNameID"
          )
        )
      )
    }

    return rows
  }

  private static func windowsNamePatchRows(
    analysis: FontAnalysis,
    font: FontDocument,
    diff: CommitDiff?
  ) -> [SaveReviewRowPresentation] {
    let analysisByID = Dictionary(uniqueKeysWithValues: analysis.windowsNameTable.map { ($0.nameID, $0.string) })
    let populated = WindowsNameTableEditing.populatedRows(
      windowsNameTable: analysis.windowsNameTable,
      overrides: font.windowsNameOverrides,
      familyPSPrefix: font.options.familyPSPrefix
    )

    return populated.map { row in
      let before = analysisByID[row.nameID]
      let after = row.value
      let category: SaveReviewDisplayCategory
      if after.isEmpty {
        category = before == nil ? .same : .removed
      } else if before == nil {
        category = .added
      } else if before != after {
        category = .renamed
      } else {
        category = .same
      }
      let afterValue: String? = after.isEmpty ? nil : SaveReviewRowFormatter.quoted(after)
      let wasLine: String? = {
        if category == .removed, let before {
          return "was \(SaveReviewRowFormatter.quoted(before))"
        }
        if category == .renamed, let before {
          return "was \(SaveReviewRowFormatter.quoted(before))"
        }
        return nil
      }()
      let fieldTitle = row.label
      let fieldSubtitle = ""
      return SaveReviewRowPresentation(
        id: "name:windows:\(row.nameID)",
        nameID: row.nameID,
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: wasLine,
        noteLine: row.nameID == 25 ? "≡ File naming PS prefix" : nil,
        roleLabel: "windows_name",
        category: category,
        searchText: SaveReviewRowFormatter.searchText(
          nameID: row.nameID,
          fieldTitle: fieldTitle,
          fieldSubtitle: fieldSubtitle,
          afterValue: afterValue,
          wasLine: wasLine,
          noteLine: row.nameID == 25 ? "PS prefix" : nil,
          roleLabel: "windows_name"
        )
      )
    }
  }

  private static func makeNameRow(
    _ row: CommitDiffNameIDRow,
    font: FontDocument,
    diff: CommitDiff?,
    tagValue: (tag: String, value: Double)?,
    axisTag: String? = nil,
    otFeatureTag: String? = nil,
    consumed: inout Set<Int>
  ) -> SaveReviewRowPresentation {
    consumed.insert(row.id)
    let category = SaveReviewDisplayCategoryMapper.category(for: row)
    let resolvedTagValue = tagValue ?? statNameIDLookup(diff: diff)[row.id]
    let resolvedOTFeature = otFeatureTag ?? otFeatureTagLookup(diff: diff)[row.id]
    let fieldTitle = SaveReviewRowFormatter.nameFieldTitle(
      row: row,
      font: font,
      tagValue: resolvedTagValue,
      axisTag: axisTag,
      otFeatureTag: resolvedOTFeature
    )
    let statFormat = diff?.statValuesPlanned.first { $0.nameID == row.id }?.statFormat
    let fieldSubtitle = SaveReviewRowFormatter.nameFieldSubtitle(
      row: row,
      tagValue: resolvedTagValue,
      statFormat: statFormat
    )
    let string = row.afterString ?? row.beforeString
    let afterValue = SaveReviewRowFormatter.nameAfterValue(string: string)
    let wasLine = SaveReviewRowFormatter.nameWasLine(row)
    let roleLabel = SaveReviewRowFormatter.nameMachineRole(role: row.afterRole)
    let noteLine = row.afterRole == "protected_ot_label" ? SaveReviewRowFormatter.fvarProtectedNote : nil
    return SaveReviewRowPresentation(
      id: "name:\(row.id)",
      nameID: row.id,
      fieldTitle: fieldTitle,
      fieldSubtitle: fieldSubtitle,
      afterValue: afterValue,
      wasLine: wasLine,
      noteLine: noteLine,
      roleLabel: roleLabel,
      category: category,
      searchText: SaveReviewRowFormatter.searchText(
        nameID: row.id,
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: wasLine,
        noteLine: noteLine,
        roleLabel: roleLabel
      )
    )
  }

  private static func makeSyntheticAxisRow(
    tag: String,
    displayName: String?,
    index: Int,
    font: FontDocument,
    diff: CommitDiff?
  ) -> SaveReviewRowPresentation {
    let axis = font.axes.first(where: { $0.tag == tag })
    let isNamingAxis = axis?.isDesignRecordOnly == true
    let fieldTitle = SaveReviewRowFormatter.designAxisFieldTitle(tag: tag, displayName: displayName)
    let fieldSubtitle = isNamingAxis
      ? "Naming axis record \(index + 1)"
      : SaveReviewRowFormatter.designAxisFieldSubtitle(index: index)
    let afterValue = SaveReviewRowFormatter.designAxisAfterValue(tag: tag)
    let noteLine = isNamingAxis ? namingAxisRegistrationNote(font: font, tag: tag) : nil
    let roleLabel = isNamingAxis ? "naming_axis" : nil
    let nameID = axisDisplayNameID(tag: tag, displayName: displayName, diff: diff)
    return SaveReviewRowPresentation(
      id: "stat:axis:\(tag)",
      nameID: nameID,
      fieldTitle: fieldTitle,
      fieldSubtitle: fieldSubtitle,
      afterValue: afterValue,
      wasLine: nil,
      noteLine: noteLine,
      roleLabel: roleLabel,
      category: .same,
      searchText: SaveReviewRowFormatter.searchText(
        nameID: nameID,
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: nil,
        noteLine: noteLine,
        roleLabel: roleLabel
      )
    )
  }

  private static func axisDisplayNameID(
    tag: String,
    displayName: String?,
    diff: CommitDiff?
  ) -> Int? {
    diff?.nameRecordsSequenced.first { record in
      guard record.role == "axis_display_name" else { return false }
      if let displayName, record.string == displayName { return true }
      return record.string == tag
    }?.id
  }

  private static func namingAxisRegistrationNote(font: FontDocument, tag: String) -> String? {
    guard let resolved = RegistrationAxisSupport.registrationStopName(
      tag: tag,
      axes: font.axes,
      fileStatRegistration: font.fileStatRegistration
    ) else {
      return "Per-file naming axis — no registered stop on this file"
    }
    var parts = ["Registered stop: \(resolved.stop.name)"]
    if let code = resolved.stop.code, !code.isEmpty {
      parts.append("code \(code)")
    }
    if resolved.elided {
      parts.append("elided in composed names")
    }
    return parts.joined(separator: " · ")
  }

  // MARK: - Helpers

  private static func tabPresentation(
    id: SaveReviewTableTab,
    label: String,
    headline: String,
    sections: [SaveReviewSectionPresentation]
  ) -> SaveReviewTabPresentation {
    let rows = sections.flatMap(\.rows)
    let changed = rows.filter(\.category.countsTowardTabChanges).count
    return SaveReviewTabPresentation(
      id: id,
      label: label,
      headline: headline,
      changedCount: changed,
      totalCount: rows.count,
      sections: sections
    )
  }

  private static func statDesignTags(font: FontDocument, analysis: FontAnalysis) -> [String] {
    let fromAxes = font.axes.map(\.tag)
    if !fromAxes.isEmpty { return fromAxes }
    if !font.statDesignAxisTags.isEmpty { return font.statDesignAxisTags }
    return analysis.designAxisTags
  }

  private static func statValueKey(tag: String, value: Double) -> String {
    "\(tag):\(AxisCoordinateFormat.format(value))"
  }

  private static func statNameIDLookup(diff: CommitDiff?) -> [Int: (String, Double)] {
    guard let diff else { return [:] }
    var map: [Int: (String, Double)] = [:]
    for item in diff.statValuesPlanned {
      if let nameID = item.nameID {
        map[nameID] = (item.tag, item.value)
      }
    }
    return map
  }

  private static func otFeatureTagLookup(diff: CommitDiff?) -> [Int: String] {
    guard let mapping = diff?.otReflowMapping else { return [:] }
    var map: [Int: String] = [:]
    for entry in mapping {
      if let feature = entry.feature, !feature.isEmpty {
        map[entry.toID] = feature
      }
    }
    return map
  }
}
