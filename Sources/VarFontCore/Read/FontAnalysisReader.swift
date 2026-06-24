import CoreText
import Foundation

public enum FontAnalysisReaderError: Error, Sendable {
    case unreadableFont(URL)
    case missingFvar
}

public enum FontAnalysisReader {
    private static let parametricTags: Set<String> = [
        "XOPQ", "YOPQ", "XTRA", "YTUC", "YTLC", "YTAS", "YTDE", "YTFI",
    ]

    private static let fvarTag = OpenTypeBinary.tag("fvar")
    private static let statTag = OpenTypeBinary.tag("STAT")
    private static let postTag = OpenTypeBinary.tag("post")

    public static func analyze(url: URL) throws -> FontAnalysis {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            throw FontAnalysisReaderError.unreadableFont(url)
        }

        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let ext = url.pathExtension.lowercased()
        let familyName = OpenTypeNameTable.name(id: 1, from: font) ?? ""
        let fullName = OpenTypeNameTable.name(id: 4, from: font) ?? ""

        let fvarData = CTFontCopyTable(font, fvarTag, []) as Data?
        let statData = CTFontCopyTable(font, statTag, []) as Data?
        let postData = CTFontCopyTable(font, postTag, []) as Data?

        var isItalicFont = false
        if let postData, postData.count >= 8 {
            let angle = OpenTypeBinary.readFixed(postData, 4)
            isItalicFont = abs(angle) > 0.5
        }

        var blockers: [String] = []
        let hasFvar = fvarData != nil
        let hasStat = statData != nil
        var hasDesignAxisRecord = false

        guard let fvarData, let fvar = FvarParser.parse(fvarData) else {
            if !hasFvar { blockers.append("No fvar table") }
            return emptyAnalysis(
                url: url,
                ext: ext,
                familyName: familyName,
                fullName: fullName,
                isItalicFont: isItalicFont,
                blockers: blockers + ["No fvar table"]
            )
        }

        let stat = statData.flatMap { StatParser.parse($0) }
        if hasStat {
            hasDesignAxisRecord = !(stat?.designAxes.isEmpty ?? true)
        }

        if !hasStat {
            blockers.append("No STAT table")
        } else if !hasDesignAxisRecord {
            blockers.append("STAT has no DesignAxisRecord")
        }

        let idxToTag = Dictionary(
            uniqueKeysWithValues: (stat?.designAxes ?? []).enumerated().map { ($0.offset, $0.element.tag) }
        )
        let orderMap = Dictionary(
            uniqueKeysWithValues: (stat?.designAxes ?? []).map { ($0.tag, $0.ordering) }
        )

        var vary: [String: Set<Double>] = [:]
        for instance in fvar.instances {
            for (tag, value) in instance.coordinates {
                vary[tag, default: []].insert(value)
            }
        }
        let gridAxisTags = vary.filter { $0.value.count > 1 }.map(\.key).sorted()

        var statValues: [FontAnalysis.StatValueRecord] = []
        for value in stat?.values ?? [] {
            let tag = idxToTag[value.axisIndex] ?? "?"
            let rec = FontAnalysis.StatValueRecord(
                format: value.format,
                tag: tag,
                name: OpenTypeNameTable.name(id: value.nameID, from: font) ?? "",
                elidable: value.elidable,
                nameID: value.nameID,
                value: value.value,
                linkedValue: value.linkedValue,
                rangeMin: value.rangeMin,
                rangeMax: value.rangeMax,
                nominal: value.nominal
            )
            statValues.append(rec)
        }

        let statByTag = Dictionary(grouping: statValues, by: \.tag)

        var axes: [FontAnalysis.AnalyzedAxis] = []
        for axis in fvar.axes {
            let role: AxisRole
            if gridAxisTags.contains(axis.tag) {
                role = .instance
            } else if parametricTags.contains(axis.tag) {
                role = .parametric
            } else {
                role = .statOnly
            }

            let valuesExisting = (statByTag[axis.tag] ?? []).map { statValue in
                FontAnalysis.StatValueSnapshot(
                    format: statValue.format,
                    value: statValue.value,
                    name: statValue.name,
                    elidable: statValue.elidable,
                    linkedValue: statValue.linkedValue,
                    rangeMin: statValue.rangeMin,
                    rangeMax: statValue.rangeMax,
                    nominal: statValue.nominal
                )
            }

            axes.append(
                FontAnalysis.AnalyzedAxis(
                    tag: axis.tag,
                    displayName: OpenTypeNameTable.name(id: axis.nameID, from: font) ?? axis.tag,
                    min: axis.min,
                    default: axis.defaultValue,
                    max: axis.max,
                    ordering: orderMap[axis.tag],
                    roleInferred: role,
                    variesInExistingInstances: gridAxisTags.contains(axis.tag),
                    valuesExisting: valuesExisting
                )
            )
        }

        let sampleCount = min(5, fvar.instances.count)
        let instancesExisting = fvar.instances.prefix(sampleCount).map { instance in
            FontAnalysis.ExistingInstance(
                key: InstanceKeyBuilder.makeKey(coords: instance.coordinates),
                composedName: OpenTypeNameTable.name(id: instance.subfamilyNameID, from: font) ?? "",
                coords: instance.coordinates,
                subfamilyNameID: instance.subfamilyNameID,
                postscriptNameID: instance.postscriptNameID
            )
        }

        let elidedFallbackID = stat?.elidedFallbackNameID
        let elidedFallbackName = elidedFallbackID.flatMap { OpenTypeNameTable.name(id: $0, from: font) }

        let additionalNamingTags = fvar.axes.map(\.tag)
            + statValues.map(\.tag)
            + gridAxisTags
        let namingOrderSuggested = NamingOrderInference.suggest(
            designAxes: stat?.designAxes ?? [],
            additionalTags: additionalNamingTags
        )

        let nameAudit = buildNameAudit(
            font: font,
            fvar: fvar,
            statValues: statValues,
            elidedFallbackID: elidedFallbackID,
            elidedFallbackName: elidedFallbackName
        )

        return FontAnalysis(
            schemaVersion: 1,
            source: FontAnalysis.SourceInfo(
                path: url.path,
                format: ext,
                familyName: familyName,
                fullName: fullName,
                isVariable: true
            ),
            readiness: FontAnalysis.Readiness(
                hasFvar: true,
                hasStat: hasStat,
                hasDesignAxisRecord: hasDesignAxisRecord,
                writable: hasStat && hasDesignAxisRecord,
                blockers: blockers
            ),
            axes: axes,
            statValues: statValues,
            instancesExisting: Array(instancesExisting),
            instancesExistingMeta: FontAnalysis.InstancesMeta(
                total: fvar.instances.count,
                sampleCount: sampleCount
            ),
            nameAudit: nameAudit,
            inferred: FontAnalysis.InferredAnalysis(
                isItalicFont: isItalicFont,
                gridAxisTags: gridAxisTags,
                namingOrderSuggested: namingOrderSuggested
            )
        )
    }

    private static func buildNameAudit(
        font: CTFont,
        fvar: (axes: [FvarAxis], instances: [FvarInstance]),
        statValues: [FontAnalysis.StatValueRecord],
        elidedFallbackID: Int?,
        elidedFallbackName: String?
    ) -> FontAnalysis.NameAudit {
        let nameData = CTFontCopyTable(font, OpenTypeBinary.tag("name"), []) as Data?
        let usedIDs = nameData.map { OpenTypeNameTable.uniqueNameIDs(in: $0) } ?? []

        var labels: [Int: String] = [:]
        for id in usedIDs {
            if let label = OpenTypeNameTable.standardNameLabel(for: id) {
                labels[id] = label
            }
        }
        for axis in fvar.axes {
            labels[axis.nameID] = "fvar axis \(axis.tag)"
        }
        for instance in fvar.instances {
            labels[instance.subfamilyNameID] = "fvar instance subfamily"
            if instance.postscriptNameID > 0, instance.postscriptNameID != 0xFFFF {
                labels[instance.postscriptNameID] = "fvar instance PostScript"
            }
        }
        for statValue in statValues {
            if let nameID = statValue.nameID {
                labels[nameID] = "STAT \(statValue.tag)"
            }
        }
        if let elidedFallbackID {
            labels[elidedFallbackID] = "STAT elided fallback"
        }

        let used = usedIDs.sorted().map { id in
            FontAnalysis.NameAudit.NameIDUse(
                id: id,
                description: labels[id] ?? "name table record",
                protected: (0...6).contains(id) ? true : nil
            )
        }

        return FontAnalysis.NameAudit(
            freeStart: OpenTypeNameTable.firstFreeNameID(used: usedIDs),
            used: used,
            elidedFallbackID: elidedFallbackID,
            elidedFallbackName: elidedFallbackName
        )
    }

    private static func emptyAnalysis(
        url: URL,
        ext: String,
        familyName: String,
        fullName: String,
        isItalicFont: Bool,
        blockers: [String]
    ) -> FontAnalysis {
        FontAnalysis(
            schemaVersion: 1,
            source: FontAnalysis.SourceInfo(
                path: url.path,
                format: ext,
                familyName: familyName,
                fullName: fullName,
                isVariable: false
            ),
            readiness: FontAnalysis.Readiness(
                hasFvar: false,
                hasStat: false,
                hasDesignAxisRecord: false,
                writable: false,
                blockers: blockers
            ),
            axes: [],
            statValues: [],
            instancesExisting: [],
            instancesExistingMeta: FontAnalysis.InstancesMeta(total: 0, sampleCount: 0),
            nameAudit: FontAnalysis.NameAudit(freeStart: 256, used: [], elidedFallbackID: nil, elidedFallbackName: nil),
            inferred: FontAnalysis.InferredAnalysis(
                isItalicFont: isItalicFont,
                gridAxisTags: [],
                namingOrderSuggested: NamingOrderInference.fallbackTags
            )
        )
    }
}
