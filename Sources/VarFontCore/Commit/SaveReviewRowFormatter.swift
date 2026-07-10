import Foundation

/// Formats `was` / `note` sublines and display values for Save Review rows.
public enum SaveReviewRowFormatter {
  // MARK: - STAT

  public static func statAfterValue(_ row: CommitDiffStatRow) -> String? {
    guard let name = row.afterName else { return nil }
    if SaveReviewDisplayCategoryMapper.statRowIsReflow(row),
       let nameID = row.afterNameID
    {
      return "nameID=\(nameID) \(quoted(name))"
    }
    if row.afterStatFormat == 3, let linked = row.afterLinkedValue {
      return "\(quoted(name)) → \(AxisCoordinateFormat.format(linked))"
    }
    return quoted(name)
  }

  public static func statWasLine(
    row: CommitDiffStatRow,
    beforeFormat: Int?
  ) -> String? {
    if SaveReviewDisplayCategoryMapper.statRowIsReflow(row) {
      let fromID = row.beforeNameID.map(String.init) ?? "?"
      let toID = row.afterNameID.map(String.init) ?? "?"
      return "nameID \(fromID) → \(toID), string unchanged"
    }
    if row.change == .removed {
      return row.beforeName.map { "was \(quoted($0))" }
    }
    if row.change == .changed, let before = row.beforeName, before != row.afterName {
      return "was \(quoted(before))"
    }
    if let beforeFormat, let afterFormat = row.afterStatFormat, beforeFormat != afterFormat {
      return "format \(beforeFormat) → format \(afterFormat)"
    }
    return nil
  }

  public static func statFieldTitle(tag: String, value: Double) -> String {
    "\(tag) = \(AxisCoordinateFormat.format(value))"
  }

  public static func statFieldSubtitle(
    row: CommitDiffStatRow,
    beforeFormat: Int?
  ) -> String {
    var parts = ["AxisValue"]
    if let nameID = row.afterNameID {
      parts.append("nameID \(nameID)")
    }
    if let format = row.afterStatFormat ?? beforeFormat {
      if format == 2 {
        parts.append("F2 range")
      } else {
        parts.append("F\(format)")
      }
    }
    return parts.joined(separator: " · ")
  }

  public static func statMachineRole(format: Int?) -> String? {
    format.map { _ in "stat_axis_value" }
  }

  public static func designAxisFieldTitle(tag: String, displayName: String?) -> String {
    if let displayName, !displayName.isEmpty {
      return "\(displayName) axis"
    }
    return "\(tag) axis"
  }

  public static func designAxisFieldSubtitle(index: Int) -> String {
    "DesignAxisRecord[\(index)]"
  }

  public static func designAxisAfterValue(tag: String) -> String {
    "tag=\(tag)"
  }

  // MARK: - fvar

  public static func instanceAfterValue(_ row: CommitDiffInstanceRow) -> String? {
    guard let name = row.afterName ?? row.beforeName else { return nil }
    return quoted(name)
  }

  public static func instanceWasLine(_ row: CommitDiffInstanceRow) -> String? {
    switch row.change {
    case .changed:
      return row.beforeName.map { "was \(quoted($0))" }
    case .removed:
      return row.beforeName.map { "was \(quoted($0))" }
    case .added:
      return "new instance"
    default:
      return nil
    }
  }

  public static func instanceSubtitle(
    coords: [String: Double]?,
    namingOrder: [String]
  ) -> String {
    guard let coords, !coords.isEmpty else { return "" }
    let extra = coords.keys.filter { !namingOrder.contains($0) }.sorted()
    let tags = namingOrder.filter { coords[$0] != nil } + extra
    return tags.compactMap { tag -> String? in
      guard let value = coords[tag] else { return nil }
      return "\(tag)=\(AxisCoordinateFormat.format(value))"
    }.joined(separator: " ")
  }

  public static let fvarProtectedNote = "read-only — design space is not written on save"

  public static func fvarAxisFieldTitle(displayName: String?, tag: String) -> String {
    let label = displayName ?? tag
    return "\(label) (\(tag))"
  }

  public static func fvarAxisFieldSubtitle(index: Int) -> String {
    "Axis[\(index)] min/default/max"
  }

  public static func fvarAxisAfterValue(min: Double?, default def: Double?, max: Double?) -> String? {
    let parts = [min, def, max].compactMap { value -> String? in
      guard let value else { return nil }
      return AxisCoordinateFormat.format(value)
    }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: " / ")
  }

  // MARK: - name IDs

  public static func nameAfterValue(id: Int, string: String?) -> String? {
    guard let string, !string.isEmpty else { return nil }
    return "\(id) \(quoted(string))"
  }

  public static func nameWasLine(_ row: CommitDiffNameIDRow) -> String? {
    if let sourceID = row.reflowedFromNameID {
      if row.beforeString == row.afterString {
        return "slot moved, string unchanged"
      }
      return "slot moved from nameID \(sourceID)"
    }
    switch row.change {
    case .changed:
      return row.beforeString.map { "was \(quoted($0))" }
    case .removed:
      return row.beforeString.map { "was \(quoted($0))" }
    case .added:
      return "new slot"
    default:
      return nil
    }
  }

  public static func nameFieldTitle(
    row: CommitDiffNameIDRow,
    font: FontDocument,
    tagValue: (tag: String, value: Double)?,
    axisTag: String? = nil
  ) -> String {
    switch row.afterRole {
    case "axis_display_name":
      if let axisTag {
        return nameAxisDisplayFieldTitle(
          displayName: row.afterString ?? row.beforeString,
          tag: axisTag
        )
      }
      if let axis = font.axes.first(where: { $0.displayName == row.afterString }) {
        return nameAxisDisplayFieldTitle(displayName: axis.displayName, tag: axis.tag)
      }
      return "Axis display"
    case "stat_axis_value":
      if let tagValue {
        return "\(tagValue.tag) = \(AxisCoordinateFormat.format(tagValue.value))"
      }
      return "STAT value"
    case "elided_fallback":
      return "Elidable fallback name"
    case "instance_subfamily":
      return "Instance subfamily"
    case "instance_postscript":
      return "PostScript name"
    case "protected_ot_label":
      return row.afterString ?? "OpenType label"
    default:
      return "nameID \(row.id)"
    }
  }

  public static func nameFieldSubtitle(
    row: CommitDiffNameIDRow,
    tagValue: (tag: String, value: Double)?
  ) -> String {
    if row.reflowedFromNameID != nil, let source = row.reflowedFromNameID {
      return "nameID \(source) → \(row.id)"
    }
    if row.afterRole == "stat_axis_value", tagValue != nil {
      return "nameID \(row.id)"
    }
    return "nameID \(row.id)"
  }

  public static func nameMachineRole(role: String?) -> String? {
    guard let role, !role.isEmpty else { return nil }
    return role
  }

  public static func nameAxisDisplayFieldTitle(displayName: String?, tag: String) -> String {
    let label = (displayName?.isEmpty == false) ? displayName! : tag
    return "\(label) (\(tag)) axis"
  }

  // MARK: - Shared

  public static func quoted(_ string: String) -> String {
    "\"\(string)\""
  }

  public static func searchText(
    fieldTitle: String,
    fieldSubtitle: String,
    afterValue: String?,
    wasLine: String?,
    noteLine: String?,
    roleLabel: String?
  ) -> String {
    [fieldTitle, fieldSubtitle, afterValue, wasLine, noteLine, roleLabel]
      .compactMap { $0 }
      .joined(separator: " ")
      .lowercased()
  }
}
