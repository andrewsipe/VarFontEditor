import Foundation

/// Derives fvar instance PostScript prefix (name ID 25) from the name table.
/// Sanitize / strip-variable rules: `PostScriptNaming` (canonical).
/// Fallback order: `derive_family_ps_prefix` in vfcommit `name_policies.py` / `nameid_allocator.py`.
public enum PostScriptPrefixInference {
    /// Priority: explicit ID 25 → ID 6 stem before hyphen → stripped ID 6 → ID 16 → ID 1.
    public static func infer(
        nameID25: String?,
        postscriptName: String?,
        typographicFamilyName: String? = nil,
        familyName: String?
    ) -> String? {
        if let from25 = cleaned(nameID25), isUsablePrefix(from25) {
            return sanitize(from25)
        }
        if let n6 = cleaned(postscriptName) {
            if let fromHyphen = stemFromPostScriptName(n6), isUsablePrefix(fromHyphen) {
                return sanitize(fromHyphen)
            }
            if let fromStripped = strippedPostScriptBase(n6), isUsablePrefix(fromStripped) {
                return sanitize(fromStripped)
            }
        }
        for candidate in [typographicFamilyName, familyName] {
            guard let raw = cleaned(candidate) else { continue }
            let base = stripVariableTokens(raw) ?? raw
            let compact = sanitize(base)
            if isUsablePrefix(compact) {
                return compact
            }
        }
        return nil
    }

    private static func stemFromPostScriptName(_ raw: String) -> String? {
        guard isUsablePrefix(raw) else { return nil }
        if let hyphen = raw.firstIndex(of: "-") {
            let stem = String(raw[..<hyphen])
            return stem.isEmpty ? nil : stem
        }
        return raw
    }

    private static func strippedPostScriptBase(_ raw: String) -> String? {
        var base = stripVariableTokens(raw) ?? raw
        for token in ["Variable", "VF"] {
            if base.hasSuffix(token) {
                base = String(base.dropLast(token.count)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            }
            let hyphenToken = "-\(token)"
            if base.hasSuffix(hyphenToken) {
                base = String(base.dropLast(hyphenToken.count)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            }
        }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Rejects clearly broken placeholders (`?`). Periods are allowed — versioned
    /// families like "Loes 0.4" / nameID 25 "Loes0.4" are valid sources.
    private static func isUsablePrefix(_ value: String) -> Bool {
        PostScriptNaming.isUsablePrefix(value)
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stripVariableTokens(_ text: String) -> String? {
        PostScriptNaming.stripVariableTokens(text)
    }

    private static func sanitize(_ value: String) -> String {
        PostScriptNaming.sanitizePostscript(value)
    }
}
