import Foundation

public struct FileClarifierInferenceResult: Equatable, Sendable {
    public var clarifiers: [FileClarifier]
    public var elidedFallbackOverride: String?

    public init(clarifiers: [FileClarifier] = [], elidedFallbackOverride: String? = nil) {
        self.clarifiers = clarifiers
        self.elidedFallbackOverride = elidedFallbackOverride
    }
}

public enum FileClarifierInference {
    public static func infer(
        sourceURL: URL,
        analysis: FontAnalysis?,
        font: FontDocument
    ) -> FileClarifierInferenceResult {
        var clarifiers: [FileClarifier] = []
        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let haystack = "\(basename) \(analysis?.source.fullName ?? "")"

        if let slope = inferSlope(haystack: haystack, analysis: analysis, font: font) {
            clarifiers.append(FileClarifier(category: .slope, label: slope))
        }
        if let width = inferWidth(haystack: haystack) {
            clarifiers.append(FileClarifier(category: .width, label: width))
        }
        if let optical = inferOptical(haystack: haystack) {
            clarifiers.append(FileClarifier(category: .optical, label: optical))
        }

        clarifiers = dedupeCategories(clarifiers)

        var elidedOverride: String?
        if clarifiers.contains(where: { $0.category == .slope }),
           let defaultName = analysis?.instancesExisting.first(where: { inst in
               inst.coords["wght"] == 400 || inst.coords["wght"] == 400.0
           })?.composedName ?? analysis?.instancesExisting.first?.composedName {
            if defaultName == "Italic" || defaultName.hasSuffix(" Italic") {
                elidedOverride = defaultName == "Italic" ? "Italic" : nil
            }
        }

        return FileClarifierInferenceResult(
            clarifiers: clarifiers,
            elidedFallbackOverride: elidedOverride
        )
    }

    private static func inferSlope(haystack: String, analysis: FontAnalysis?, font: FontDocument) -> String? {
        let lower = haystack.lowercased()
        if lower.contains("oblique") { return "Oblique" }
        if lower.contains("italic") { return "Italic" }
        if analysis?.inferred.isItalicFont == true { return "Italic" }
        if font.axes.contains(where: { $0.tag == "ital" && $0.role == .instance }) { return nil }
        if font.axes.contains(where: { $0.tag == "ital" && $0.isDesignRecordOnly }) { return nil }
        let names = font.axes.flatMap(\.values).map(\.name)
        if names.contains(where: { $0.localizedCaseInsensitiveContains("italic") }) {
            return "Italic"
        }
        return nil
    }

    private static func inferWidth(haystack: String) -> String? {
        let lower = haystack.lowercased()
        if lower.contains("semicond") { return "SemiCondensed" }
        if lower.contains("condensed") || lower.contains("cond") { return "Condensed" }
        if lower.contains("extended") || lower.contains(" wide") || lower.hasSuffix("wide") { return "Wide" }
        return nil
    }

    private static func inferOptical(haystack: String) -> String? {
        let lower = haystack.lowercased()
        if lower.contains("micro") { return "Micro" }
        if lower.contains("display") { return "Display" }
        if lower.contains("text") && !lower.contains("texture") { return "Text" }
        return nil
    }

    private static func dedupeCategories(_ clarifiers: [FileClarifier]) -> [FileClarifier] {
        var seen = Set<FileClarifierCategory>()
        var result: [FileClarifier] = []
        for item in clarifiers {
            guard !seen.contains(item.category) else { continue }
            seen.insert(item.category)
            result.append(item)
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
