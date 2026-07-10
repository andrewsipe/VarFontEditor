import Foundation

public enum SaveReviewPresentationBuilder {
  public static func build(
    analysis: FontAnalysis,
    font: FontDocument,
    plan: InstancePlan,
    report: CommitDiffReport,
    diff: CommitDiff?
  ) -> SaveReviewPresentation {
    let namingOrder = analysis.inferred.namingOrderSuggested
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
        return makeSyntheticAxisRow(tag: tag, displayName: displayName, index: index)
      }
      sections.append(SaveReviewSectionPresentation(title: "Axis records", rows: axisRows))
    }

    let beforeFormatByKey = Dictionary(
      uniqueKeysWithValues: analysis.statValues.map {
        (statValueKey(tag: $0.tag, value: $0.value ?? $0.nominal ?? 0), $0.format)
      }
    )

    for tag in font.axes.map(\.tag) {
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
        let fieldSubtitle = SaveReviewRowFormatter.statFieldSubtitle(row: row, beforeFormat: beforeFormat)
        let roleLabel = SaveReviewRowFormatter.statMachineRole(format: row.afterStatFormat)
        return SaveReviewRowPresentation(
          id: "stat:\(key)",
          fieldTitle: fieldTitle,
          fieldSubtitle: fieldSubtitle,
          afterValue: afterValue,
          wasLine: wasLine,
          noteLine: nil,
          roleLabel: roleLabel,
          category: category,
          searchText: SaveReviewRowFormatter.searchText(
            fieldTitle: fieldTitle,
            fieldSubtitle: fieldSubtitle,
            afterValue: afterValue,
            wasLine: wasLine,
            noteLine: nil,
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
    let fieldSubtitle = "elidedFallbackNameID"
    let afterValue = afterName.map { SaveReviewRowFormatter.quoted($0) }
    let wasLine = category == .renamed ? beforeName.map { "was \(SaveReviewRowFormatter.quoted($0))" } : nil
    return SaveReviewRowPresentation(
      id: "stat:elided",
      fieldTitle: fieldTitle,
      fieldSubtitle: fieldSubtitle,
      afterValue: afterValue,
      wasLine: wasLine,
      noteLine: nil,
      roleLabel: nil,
      category: category,
      searchText: SaveReviewRowFormatter.searchText(
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
    namingOrder: [String]
  ) -> SaveReviewTabPresentation {
    var sections: [SaveReviewSectionPresentation] = []

    let fvarAxes = font.axes.filter(\.hasFvarScale)
    let axisRows = fvarAxes.enumerated().map { index, axis -> SaveReviewRowPresentation in
      let noteParts = fvarAxisNoteLines(axisTag: axis.tag, analysis: analysis, font: font)
      let noteLine = noteParts.isEmpty
        ? SaveReviewRowFormatter.fvarProtectedNote
        : ([SaveReviewRowFormatter.fvarProtectedNote] + noteParts).joined(separator: " · ")
      let fieldTitle = SaveReviewRowFormatter.fvarAxisFieldTitle(displayName: axis.displayName, tag: axis.tag)
      let fieldSubtitle = SaveReviewRowFormatter.fvarAxisFieldSubtitle(index: index)
      let afterValue = SaveReviewRowFormatter.fvarAxisAfterValue(
        min: axis.min,
        default: axis.default,
        max: axis.max
      )
      return SaveReviewRowPresentation(
        id: "fvar:axis:\(axis.tag)",
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
      sections.append(SaveReviewSectionPresentation(title: "Axes", rows: axisRows))
    }

    let instanceRows = report.instanceRows.enumerated().map { index, row -> SaveReviewRowPresentation in
      let category = SaveReviewDisplayCategoryMapper.category(for: row)
      let fieldTitle = "Instance \(index + 1)"
      let fieldSubtitle = SaveReviewRowFormatter.instanceSubtitle(
        coords: row.coords,
        namingOrder: namingOrder
      )
      let afterValue = SaveReviewRowFormatter.instanceAfterValue(row)
      let wasLine = SaveReviewRowFormatter.instanceWasLine(row)
      return SaveReviewRowPresentation(
        id: "fvar:instance:\(row.key)",
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: wasLine,
        noteLine: nil,
        roleLabel: nil,
        category: category,
        searchText: SaveReviewRowFormatter.searchText(
          fieldTitle: fieldTitle,
          fieldSubtitle: fieldSubtitle,
          afterValue: afterValue,
          wasLine: wasLine,
          noteLine: nil,
          roleLabel: nil
        )
      )
    }
    sections.append(SaveReviewSectionPresentation(title: "Instances", rows: instanceRows))

    return tabPresentation(
      id: .fvar,
      label: SaveReviewTableTab.fvar.label,
      headline: "fvar instances (axes are read-only)",
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
    var consumedIDs = Set<Int>()
    var sections: [SaveReviewSectionPresentation] = []

    var axisDisplayRows: [SaveReviewRowPresentation] = []
    let sequenced = diff?.nameRecordsSequenced ?? []
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

  private static func makeNameRow(
    _ row: CommitDiffNameIDRow,
    font: FontDocument,
    diff: CommitDiff?,
    tagValue: (tag: String, value: Double)?,
    axisTag: String? = nil,
    consumed: inout Set<Int>
  ) -> SaveReviewRowPresentation {
    consumed.insert(row.id)
    let category = SaveReviewDisplayCategoryMapper.category(for: row)
    let resolvedTagValue = tagValue ?? statNameIDLookup(diff: diff)[row.id]
    let fieldTitle = SaveReviewRowFormatter.nameFieldTitle(
      row: row,
      font: font,
      tagValue: resolvedTagValue,
      axisTag: axisTag
    )
    let fieldSubtitle = SaveReviewRowFormatter.nameFieldSubtitle(row: row, tagValue: resolvedTagValue)
    let string = row.afterString ?? row.beforeString
    let afterValue = SaveReviewRowFormatter.nameAfterValue(id: row.id, string: string)
    let wasLine = SaveReviewRowFormatter.nameWasLine(row)
    let roleLabel = SaveReviewRowFormatter.nameMachineRole(role: row.afterRole)
    let noteLine = row.afterRole == "protected_ot_label" ? SaveReviewRowFormatter.fvarProtectedNote : nil
    return SaveReviewRowPresentation(
      id: "name:\(row.id)",
      fieldTitle: fieldTitle,
      fieldSubtitle: fieldSubtitle,
      afterValue: afterValue,
      wasLine: wasLine,
      noteLine: noteLine,
      roleLabel: roleLabel,
      category: category,
      searchText: SaveReviewRowFormatter.searchText(
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: wasLine,
        noteLine: noteLine,
        roleLabel: roleLabel
      )
    )
  }

  private static func makeSyntheticAxisRow(tag: String, displayName: String?, index: Int) -> SaveReviewRowPresentation {
    let fieldTitle = SaveReviewRowFormatter.designAxisFieldTitle(tag: tag, displayName: displayName)
    let fieldSubtitle = SaveReviewRowFormatter.designAxisFieldSubtitle(index: index)
    let afterValue = SaveReviewRowFormatter.designAxisAfterValue(tag: tag)
    return SaveReviewRowPresentation(
      id: "stat:axis:\(tag)",
      fieldTitle: fieldTitle,
      fieldSubtitle: fieldSubtitle,
      afterValue: afterValue,
      wasLine: nil,
      noteLine: nil,
      roleLabel: nil,
      category: .same,
      searchText: SaveReviewRowFormatter.searchText(
        fieldTitle: fieldTitle,
        fieldSubtitle: fieldSubtitle,
        afterValue: afterValue,
        wasLine: nil,
        noteLine: nil,
        roleLabel: nil
      )
    )
  }

  // MARK: - Helpers

  private static func tabPresentation(
    id: SaveReviewTableTab,
    label: String,
    headline: String,
    sections: [SaveReviewSectionPresentation]
  ) -> SaveReviewTabPresentation {
    let rows = sections.flatMap(\.rows)
    let changed = rows.filter { $0.category != .same }.count
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
}
