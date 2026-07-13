import Foundation

/// Builds fvar PostScript instance names from naming order and a movable `@pshyphen` split.
///
/// **Canonical PostScript string rules** (shared with `PostScriptPrefixInference` and vfcommit
/// `name_policies.py` — keep all three in sync):
///
/// - **Sanitize:** remove spaces, then replace any character outside
///   `A–Z a–z 0–9 - . _ ? ! & *` with `-`.
/// - **Strip variable tokens:** remove whole-word `Variable`, `VF`, `GX`, `Flex` (case-insensitive),
///   then boundary-delimited suffix forms such as `-Variable`, `-VF`, ` VariableItalic`, etc.
/// - **Prefix usability:** reject empty strings and any value containing `?` before prefix inference.
public enum PostScriptNaming {
    public static func composeInstanceName(
        familyPrefix: String,
        coords: [String: Double],
        axes: [AxisDefinition],
        naming: NamingPolicy,
        fileRole: FileRole? = nil,
        fileStatRegistration: [String: Double] = [:]
    ) -> String {
        let composed = NamingComposer.compose(
            coords: coords,
            axes: axes,
            naming: naming,
            fileRole: fileRole,
            fileStatRegistration: fileStatRegistration
        )
        let style = composeStyleSegment(
            coords: coords,
            axes: axes,
            naming: naming,
            fileRole: fileRole,
            fileStatRegistration: fileStatRegistration,
            elidedFallback: composed.name
        )
        return composeFullName(familyPrefix: familyPrefix, styleSegment: style)
    }

    public static func composeStyleSegment(
        coords: [String: Double],
        axes: [AxisDefinition],
        naming: NamingPolicy,
        fileRole: FileRole? = nil,
        fileStatRegistration: [String: Double] = [:],
        elidedFallback: String = "Regular"
    ) -> String {
        let order = NamingPolicy.mergedOrder(
            projectOrder: naming.order,
            axisTags: axes.map(\.tag)
        )
        var beforeHyphen: [String] = []
        var afterHyphen: [String] = []
        var pastHyphen = false

        let axisByTag = Dictionary(uniqueKeysWithValues: axes.map { ($0.tag, $0) })
        let coveredClarifiers = RegistrationAxisSupport.clarifierCategoriesCoveredByRegistration(
            axes: axes,
            fileStatRegistration: fileStatRegistration
        )

        for token in order {
            if NamingToken.isPostscriptHyphen(token) {
                pastHyphen = true
                continue
            }

            guard let part = namingPart(
                token: token,
                coords: coords,
                axisByTag: axisByTag,
                fileRole: fileRole,
                fileStatRegistration: fileStatRegistration,
                coveredClarifiers: coveredClarifiers
            ) else { continue }

            if pastHyphen {
                afterHyphen.append(part)
            } else {
                beforeHyphen.append(part)
            }
        }

        let before = sanitizePostscript(beforeHyphen.joined())
        let after = sanitizePostscript(afterHyphen.joined())

        if before.isEmpty { return after.isEmpty ? sanitizePostscript(elidedFallback) : after }
        if after.isEmpty { return before }
        return "\(before)-\(after)"
    }

    public static func composeFullName(familyPrefix: String, styleSegment: String) -> String {
        let prefix = sanitizePostscript(familyPrefix.trimmingCharacters(in: .whitespacesAndNewlines))
        let normalizedPrefix = prefix.isEmpty ? "Font" : prefix
        let style = sanitizePostscript(styleSegment.trimmingCharacters(in: .whitespacesAndNewlines))
        if style.isEmpty || style.caseInsensitiveCompare("Regular") == .orderedSame {
            return "\(normalizedPrefix)-Regular"
        }
        if let hyphen = style.firstIndex(of: "-") {
            let before = String(style[..<hyphen])
            let after = String(style[style.index(after: hyphen)...])
            if after.isEmpty {
                return "\(normalizedPrefix)-\(before)"
            }
            return "\(normalizedPrefix)\(before)-\(after)"
        }
        return "\(normalizedPrefix)-\(style)"
    }

    public static func sanitizePostscript(_ value: String) -> String {
        let noSpaces = value.replacingOccurrences(of: " ", with: "")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._?!&*"))
        return String(noSpaces.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    /// Strips Variable/VF/GX/Flex tokens from family-like strings before prefix inference.
    public static func stripVariableTokens(_ text: String) -> String? {
        var s = text
        let pattern = #"\b(Variable|VF|GX|Flex)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        for pattern in [
            #"(?i)(?:^|[-_\s])Variable(?:Italic)?(?=$|[-_\s])"#,
            #"(?i)(?:^|[-_\s])(VF|GX|Flex)(?=$|[-_\s])"#,
        ] {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: " ")
            }
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Rejects clearly broken placeholders (`?`). Periods are allowed — versioned families are valid.
    public static func isUsablePrefix(_ value: String) -> Bool {
        if value.isEmpty { return false }
        if value.contains("?") { return false }
        return true
    }

    // MARK: - Private

    private static func namingPart(
        token: String,
        coords: [String: Double],
        axisByTag: [String: AxisDefinition],
        fileRole: FileRole?,
        fileStatRegistration: [String: Double],
        coveredClarifiers: Set<FileClarifierCategory>
    ) -> String? {
        if NamingToken.isClarifier(token) {
            guard let category = NamingToken.clarifierCategory(for: token),
                  !coveredClarifiers.contains(category),
                  let label = fileRole?.label(for: category) else { return nil }
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let axis = axisByTag[token], axis.isDesignRecordOnly {
            guard let resolved = RegistrationAxisSupport.registrationStopName(
                tag: token,
                axes: Array(axisByTag.values),
                fileStatRegistration: fileStatRegistration
            ), !resolved.elided else { return nil }
            return resolved.stop.name
        }

        guard let axis = axisByTag[token],
              axis.role == .instance,
              let value = coords[token],
              let stop = AxisCoordinate.matchingStop(in: axis.values, coordinate: value),
              !stop.elidable else { return nil }
        return stop.name
    }
}
