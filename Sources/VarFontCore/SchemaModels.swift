import Foundation

// MARK: - Shared

public enum AxisRole: String, Codable, Sendable, CaseIterable {
    case instance
    case statOnly = "stat_only"
    case parametric
    /// STAT DesignAxisRecord axis with no corresponding fvar scale.
    case designRecordOnly = "design_record_only"
}

public struct AxisValue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var value: Double
    public var name: String
    public var elidable: Bool
    public var olderSibling: Bool
    public var statFormat: Int
    public var rangeMin: Double?
    public var rangeMax: Double?
    public var linkedValue: Double?

    enum CodingKeys: String, CodingKey {
        case id, value, name, elidable
        case olderSibling = "older_sibling"
        case statFormat = "stat_format"
        case rangeMin = "range_min"
        case rangeMax = "range_max"
        case linkedValue = "linked_value"
    }

    public init(
        id: String,
        value: Double,
        name: String,
        elidable: Bool,
        olderSibling: Bool = false,
        statFormat: Int = 1,
        rangeMin: Double? = nil,
        rangeMax: Double? = nil,
        linkedValue: Double? = nil
    ) {
        self.id = id
        self.value = value
        self.name = name
        self.elidable = elidable
        self.olderSibling = olderSibling
        self.statFormat = statFormat
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
        self.linkedValue = linkedValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        value = try c.decode(Double.self, forKey: .value)
        name = try c.decode(String.self, forKey: .name)
        elidable = try c.decode(Bool.self, forKey: .elidable)
        olderSibling = try c.decodeIfPresent(Bool.self, forKey: .olderSibling) ?? false
        statFormat = try c.decodeIfPresent(Int.self, forKey: .statFormat) ?? 1
        rangeMin = try c.decodeIfPresent(Double.self, forKey: .rangeMin)
        rangeMax = try c.decodeIfPresent(Double.self, forKey: .rangeMax)
        linkedValue = try c.decodeIfPresent(Double.self, forKey: .linkedValue)
    }
}

/// STAT format 4 compound multi-axis entry preserved from source font.
public struct CompoundStatValue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var coords: [String: Double]
    public var axisIndices: [Int]
    public var axisValues: [Double]
    public var name: String
    public var elidable: Bool
    public var olderSibling: Bool

    enum CodingKeys: String, CodingKey {
        case id, coords, name, elidable
        case axisIndices = "axis_indices"
        case axisValues = "axis_values"
        case olderSibling = "older_sibling"
    }

    public init(
        id: String,
        coords: [String: Double],
        axisIndices: [Int],
        axisValues: [Double],
        name: String,
        elidable: Bool,
        olderSibling: Bool = false
    ) {
        self.id = id
        self.coords = coords
        self.axisIndices = axisIndices
        self.axisValues = axisValues
        self.name = name
        self.elidable = elidable
        self.olderSibling = olderSibling
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        coords = try c.decode([String: Double].self, forKey: .coords)
        axisIndices = try c.decodeIfPresent([Int].self, forKey: .axisIndices) ?? []
        axisValues = try c.decodeIfPresent([Double].self, forKey: .axisValues) ?? []
        name = try c.decode(String.self, forKey: .name)
        elidable = try c.decode(Bool.self, forKey: .elidable)
        olderSibling = try c.decodeIfPresent(Bool.self, forKey: .olderSibling) ?? false
    }
}

public struct AxisDefinition: Codable, Equatable, Sendable, Identifiable {
    public var tag: String
    public var displayName: String?
    public var min: Double?
    public var `default`: Double?
    public var max: Double?
    public var role: AxisRole
    /// Role inferred at import; used by Restore in the naming chain footer.
    public var roleInferred: AxisRole?
    public var values: [AxisValue]
    public var referenceMapping: ReferenceMappingKind?
    public var referenceMappingInferred: ReferenceMappingKind?
    public var referenceAnchors: [ReferenceAnchor]
    /// fvar HIDDEN_AXIS flag from source (recommend axis stay out of user-facing UIs).
    public var fvarHidden: Bool

    public var id: String { tag }

    enum CodingKeys: String, CodingKey {
        case tag
        case displayName = "display_name"
        case min, `default`, max, role
        case roleInferred = "role_inferred"
        case values
        case referenceMapping = "reference_mapping"
        case referenceMappingInferred = "reference_mapping_inferred"
        case referenceAnchors = "reference_anchors"
        case fvarHidden = "fvar_hidden"
    }

    public init(
        tag: String,
        displayName: String? = nil,
        min: Double? = nil,
        default: Double? = nil,
        max: Double? = nil,
        role: AxisRole = .instance,
        roleInferred: AxisRole? = nil,
        values: [AxisValue] = [],
        referenceMapping: ReferenceMappingKind? = nil,
        referenceMappingInferred: ReferenceMappingKind? = nil,
        referenceAnchors: [ReferenceAnchor] = [],
        fvarHidden: Bool = false
    ) {
        self.tag = tag
        self.displayName = displayName
        self.min = min
        self.default = `default`
        self.max = max
        self.role = role
        self.roleInferred = roleInferred
        self.values = values
        self.referenceMapping = referenceMapping
        self.referenceMappingInferred = referenceMappingInferred
        self.referenceAnchors = referenceAnchors
        self.fvarHidden = fvarHidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.decode(String.self, forKey: .tag)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        `default` = try c.decodeIfPresent(Double.self, forKey: .default)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
        role = try c.decodeIfPresent(AxisRole.self, forKey: .role) ?? .instance
        roleInferred = try c.decodeIfPresent(AxisRole.self, forKey: .roleInferred)
        values = try c.decodeIfPresent([AxisValue].self, forKey: .values) ?? []
        referenceMapping = try c.decodeIfPresent(ReferenceMappingKind.self, forKey: .referenceMapping)
        referenceMappingInferred = try c.decodeIfPresent(ReferenceMappingKind.self, forKey: .referenceMappingInferred)
        referenceAnchors = try c.decodeIfPresent([ReferenceAnchor].self, forKey: .referenceAnchors) ?? []
        fvarHidden = try c.decodeIfPresent(Bool.self, forKey: .fvarHidden) ?? false
    }

    /// True when this axis exists only in STAT DesignAxisRecord (no fvar scale).
    public var isDesignRecordOnly: Bool { role == .designRecordOnly }

    /// True when fvar min/default/max apply to this axis.
    public var hasFvarScale: Bool { min != nil }
}

public struct NamingPolicy: Codable, Equatable, Sendable {
    public var order: [String]
    /// STAT-inferred order captured at import; used by Restore in the naming chain footer.
    public var inferredOrder: [String]?
    public var elidedFallback: String

    enum CodingKeys: String, CodingKey {
        case order
        case inferredOrder = "inferred_order"
        case elidedFallback = "elided_fallback"
    }

    public static let clarifierTokenWidth = "@width"
    public static let clarifierTokenSlope = "@slope"
    public static let clarifierTokenOptical = "@optical"
    public static let clarifierTokenCustom = "@custom"
    public static let postscriptHyphenToken = "@pshyphen"

    public static let defaultClarifierTokens: [String] = [
        clarifierTokenWidth,
        clarifierTokenSlope,
        clarifierTokenOptical,
        clarifierTokenCustom
    ]

    public init(order: [String], inferredOrder: [String]? = nil, elidedFallback: String = "Regular") {
        self.order = order
        self.inferredOrder = inferredOrder
        self.elidedFallback = elidedFallback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode([String].self, forKey: .order)
        inferredOrder = try c.decodeIfPresent([String].self, forKey: .inferredOrder)
        elidedFallback = try c.decodeIfPresent(String.self, forKey: .elidedFallback) ?? "Regular"
    }

    /// Appends default clarifier tokens to axis order when missing.
    public static func orderWithDefaultClarifiers(axisOrder: [String]) -> [String] {
        var result = axisOrder.filter { !NamingToken.isSpecialToken($0) }
        for token in defaultClarifierTokens where !result.contains(token) {
            result.append(token)
        }
        return ensurePostscriptHyphen(in: result)
    }

    /// Ensures exactly one PS hyphen marker exists (default: first in the chain).
    public static func ensurePostscriptHyphen(in order: [String]) -> [String] {
        let without = order.filter { $0 != postscriptHyphenToken }
        if let originalIndex = order.firstIndex(of: postscriptHyphenToken) {
            var result = without
            let insertAt = min(originalIndex, result.count)
            result.insert(postscriptHyphenToken, at: insertAt)
            return result
        }
        var result = without
        result.insert(postscriptHyphenToken, at: 0)
        return result
    }

    /// Restore helper — PS hyphen returns to the default first position.
    public static func resetPostscriptHyphenToDefault(in order: [String]) -> [String] {
        ensurePostscriptHyphen(in: order.filter { $0 != postscriptHyphenToken })
    }

    /// Project naming order filtered to axes present in this file plus clarifier tokens.
    public static func mergedOrder(projectOrder: [String], axisTags: [String]) -> [String] {
        var result: [String] = []
        var seenAxes = Set<String>()
        var seenClarifiers = Set<String>()
        var hasHyphen = false

        for token in projectOrder {
            if NamingToken.isPostscriptHyphen(token) {
                if !hasHyphen {
                    result.append(postscriptHyphenToken)
                    hasHyphen = true
                }
                continue
            }
            if NamingToken.isClarifier(token) {
                guard !seenClarifiers.contains(token) else { continue }
                result.append(token)
                seenClarifiers.insert(token)
            } else if axisTags.contains(token), !seenAxes.contains(token) {
                result.append(token)
                seenAxes.insert(token)
            }
        }

        for tag in axisTags where !seenAxes.contains(tag) {
            result.append(tag)
        }
        for token in defaultClarifierTokens where !seenClarifiers.contains(token) {
            result.append(token)
        }
        if !hasHyphen {
            result.insert(postscriptHyphenToken, at: 0)
        }
        return result
    }
}

public enum NamingToken {
    public static func isPostscriptHyphen(_ token: String) -> Bool {
        token == NamingPolicy.postscriptHyphenToken
    }

    public static func isSpecialToken(_ token: String) -> Bool {
        isPostscriptHyphen(token) || isClarifier(token)
    }

    public static func isClarifier(_ token: String) -> Bool {
        guard !isPostscriptHyphen(token) else { return false }
        return token.hasPrefix("@")
    }

    public static func clarifierCategory(for token: String) -> FileClarifierCategory? {
        switch token {
        case NamingPolicy.clarifierTokenWidth: return .width
        case NamingPolicy.clarifierTokenSlope: return .slope
        case NamingPolicy.clarifierTokenOptical: return .optical
        case NamingPolicy.clarifierTokenCustom: return .custom
        default: return nil
        }
    }

    public static func token(for category: FileClarifierCategory) -> String {
        switch category {
        case .width: return NamingPolicy.clarifierTokenWidth
        case .slope: return NamingPolicy.clarifierTokenSlope
        case .optical: return NamingPolicy.clarifierTokenOptical
        case .custom: return NamingPolicy.clarifierTokenCustom
        }
    }

    public static func clarifierPillLabel(for category: FileClarifierCategory) -> String {
        switch category {
        case .width: return "Width"
        case .slope: return "Slope"
        case .optical: return "Optical"
        case .custom: return "Custom"
        }
    }

    public static var clarifierDisplayName: [String: String] {
        [
            NamingPolicy.clarifierTokenWidth: "width",
            NamingPolicy.clarifierTokenSlope: "slope",
            NamingPolicy.clarifierTokenOptical: "optical",
            NamingPolicy.clarifierTokenCustom: "custom"
        ]
    }
}

// MARK: - File clarifiers (per-font family identity)

public enum FileClarifierCategory: String, Codable, Sendable, CaseIterable {
    case slope
    case width
    case optical
    case custom
}

public enum FileRoleKind: String, Codable, Sendable {
    case master
    case variant
}

public struct FileClarifier: Codable, Equatable, Sendable, Identifiable {
    public var category: FileClarifierCategory
    public var label: String

    public var id: FileClarifierCategory { category }

    enum CodingKeys: String, CodingKey {
        case category, label
    }

    public init(category: FileClarifierCategory, label: String) {
        self.category = category
        self.label = label
    }
}

public struct FileRole: Codable, Equatable, Sendable {
    public var kind: FileRoleKind
    public var masterFontID: String?
    public var clarifiers: [FileClarifier]
    public var elidedFallbackOverride: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case masterFontID = "master_font_id"
        case clarifiers
        case elidedFallbackOverride = "elided_fallback_override"
    }

    public init(
        kind: FileRoleKind = .master,
        masterFontID: String? = nil,
        clarifiers: [FileClarifier] = [],
        elidedFallbackOverride: String? = nil
    ) {
        self.kind = kind
        self.masterFontID = masterFontID
        self.clarifiers = clarifiers
        self.elidedFallbackOverride = elidedFallbackOverride
    }

    public func label(for category: FileClarifierCategory) -> String? {
        clarifiers.first { $0.category == category }?.label
    }

    public static func master() -> FileRole {
        FileRole(kind: .master)
    }

    public static func variant(masterFontID: String, clarifiers: [FileClarifier] = [], elidedFallbackOverride: String? = nil) -> FileRole {
        FileRole(
            kind: .variant,
            masterFontID: masterFontID,
            clarifiers: clarifiers,
            elidedFallbackOverride: elidedFallbackOverride
        )
    }
}

public enum NameIDStrategy: String, Codable, Equatable, Sendable {
    case preserve
    case reflow
}

public struct CommitOptions: Codable, Equatable, Sendable {
    public var fixFvarDefault: Bool
    public var allocatePostscriptNames: Bool
    public var preserveStatFormat3: Bool?
    /// nameID 25 — prefix for fvar instance PostScript names (e.g. FamilyVariable).
    public var familyPSPrefix: String?
    /// How OpenType feature label nameIDs (ss/cv/size) are handled on save.
    public var nameidStrategy: NameIDStrategy

    enum CodingKeys: String, CodingKey {
        case fixFvarDefault = "fix_fvar_default"
        case allocatePostscriptNames = "allocate_postscript_names"
        case preserveStatFormat3 = "preserve_stat_format_3"
        case familyPSPrefix = "family_ps_prefix"
        case nameidStrategy = "nameid_strategy"
    }

    public init(
        fixFvarDefault: Bool = false,
        allocatePostscriptNames: Bool = true,
        preserveStatFormat3: Bool? = true,
        familyPSPrefix: String? = nil,
        nameidStrategy: NameIDStrategy = .preserve
    ) {
        self.fixFvarDefault = fixFvarDefault
        self.allocatePostscriptNames = allocatePostscriptNames
        self.preserveStatFormat3 = preserveStatFormat3
        self.familyPSPrefix = familyPSPrefix
        self.nameidStrategy = nameidStrategy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fixFvarDefault = try c.decodeIfPresent(Bool.self, forKey: .fixFvarDefault) ?? false
        allocatePostscriptNames = try c.decodeIfPresent(Bool.self, forKey: .allocatePostscriptNames) ?? true
        preserveStatFormat3 = try c.decodeIfPresent(Bool.self, forKey: .preserveStatFormat3)
        familyPSPrefix = try c.decodeIfPresent(String.self, forKey: .familyPSPrefix)
        nameidStrategy = try c.decodeIfPresent(NameIDStrategy.self, forKey: .nameidStrategy) ?? .preserve
    }
}

// MARK: - FontAnalysis

public struct FontAnalysis: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var source: SourceInfo
    public var readiness: Readiness
    public var axes: [AnalyzedAxis]
    public var statValues: [StatValueRecord]
    public var compoundStatValues: [CompoundStatRecord]
    public var instancesExisting: [ExistingInstance]
    public var instancesExistingMeta: InstancesMeta?
    public var nameAudit: NameAudit
    public var inferred: InferredAnalysis
    /// STAT DesignAxisRecord tags in table order (fvar parity checks).
    public var designAxisTags: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source, readiness, axes
        case statValues = "stat_values"
        case compoundStatValues = "compound_stat_values"
        case instancesExisting = "instances_existing"
        case instancesExistingMeta = "instances_existing_meta"
        case nameAudit = "name_audit"
        case inferred
        case designAxisTags = "design_axis_tags"
    }

    public struct SourceInfo: Codable, Equatable, Sendable {
        public var path: String
        public var format: String
        public var familyName: String
        public var fullName: String
        public var postscriptName: String?
        public var isVariable: Bool
        /// nameID 25 — Variations PostScript Name Prefix.
        public var familyPSPrefix: String?

        enum CodingKeys: String, CodingKey {
            case path, format
            case familyName = "family_name"
            case fullName = "full_name"
            case postscriptName = "postscript_name"
            case isVariable = "is_variable"
            case familyPSPrefix = "family_ps_prefix"
        }
    }

    public struct Readiness: Codable, Equatable, Sendable {
        public var hasFvar: Bool
        public var hasStat: Bool
        public var hasDesignAxisRecord: Bool
        public var writable: Bool
        public var blockers: [String]

        enum CodingKeys: String, CodingKey {
            case hasFvar = "has_fvar"
            case hasStat = "has_stat"
            case hasDesignAxisRecord = "has_design_axis_record"
            case writable, blockers
        }
    }

    public struct AnalyzedAxis: Codable, Equatable, Sendable, Identifiable {
        public var tag: String
        public var displayName: String
        public var min: Double
        public var `default`: Double
        public var max: Double
        public var ordering: Int?
        public var roleInferred: AxisRole
        public var variesInExistingInstances: Bool
        public var valuesExisting: [StatValueSnapshot]
        public var fvarHidden: Bool?

        public var id: String { tag }

        enum CodingKeys: String, CodingKey {
            case tag
            case displayName = "display_name"
            case min, `default`, max, ordering
            case roleInferred = "role_inferred"
            case variesInExistingInstances = "varies_in_existing_instances"
            case valuesExisting = "values_existing"
            case fvarHidden = "fvar_hidden"
        }
    }

    public struct StatValueSnapshot: Codable, Equatable, Sendable {
        public var format: Int?
        public var value: Double?
        public var name: String
        public var elidable: Bool?
        public var olderSibling: Bool?
        public var linkedValue: Double?
        public var rangeMin: Double?
        public var rangeMax: Double?
        public var nominal: Double?

        enum CodingKeys: String, CodingKey {
            case format, value, name, elidable
            case olderSibling = "older_sibling"
            case linkedValue = "linked_value"
            case rangeMin = "range_min"
            case rangeMax = "range_max"
            case nominal
        }
    }

    public struct StatValueRecord: Codable, Equatable, Sendable {
        public var format: Int
        public var tag: String
        public var name: String
        public var elidable: Bool
        public var olderSibling: Bool
        public var nameID: Int?
        public var value: Double?
        public var linkedValue: Double?
        public var rangeMin: Double?
        public var rangeMax: Double?
        public var nominal: Double?

        enum CodingKeys: String, CodingKey {
            case format, tag, name, elidable
            case olderSibling = "older_sibling"
            case nameID = "name_id"
            case value
            case linkedValue = "linked_value"
            case rangeMin = "range_min"
            case rangeMax = "range_max"
            case nominal
        }

        public init(
            format: Int,
            tag: String,
            name: String,
            elidable: Bool,
            olderSibling: Bool = false,
            nameID: Int? = nil,
            value: Double? = nil,
            linkedValue: Double? = nil,
            rangeMin: Double? = nil,
            rangeMax: Double? = nil,
            nominal: Double? = nil
        ) {
            self.format = format
            self.tag = tag
            self.name = name
            self.elidable = elidable
            self.olderSibling = olderSibling
            self.nameID = nameID
            self.value = value
            self.linkedValue = linkedValue
            self.rangeMin = rangeMin
            self.rangeMax = rangeMax
            self.nominal = nominal
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(Int.self, forKey: .format)
            tag = try c.decode(String.self, forKey: .tag)
            name = try c.decode(String.self, forKey: .name)
            elidable = try c.decode(Bool.self, forKey: .elidable)
            olderSibling = try c.decodeIfPresent(Bool.self, forKey: .olderSibling) ?? false
            nameID = try c.decodeIfPresent(Int.self, forKey: .nameID)
            value = try c.decodeIfPresent(Double.self, forKey: .value)
            linkedValue = try c.decodeIfPresent(Double.self, forKey: .linkedValue)
            rangeMin = try c.decodeIfPresent(Double.self, forKey: .rangeMin)
            rangeMax = try c.decodeIfPresent(Double.self, forKey: .rangeMax)
            nominal = try c.decodeIfPresent(Double.self, forKey: .nominal)
        }
    }

    public struct CompoundStatRecord: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var coords: [String: Double]
        public var axisIndices: [Int]
        public var axisValues: [Double]
        public var name: String
        public var elidable: Bool
        public var olderSibling: Bool
        public var nameID: Int?

        enum CodingKeys: String, CodingKey {
            case id, coords, name, elidable
            case axisIndices = "axis_indices"
            case axisValues = "axis_values"
            case olderSibling = "older_sibling"
            case nameID = "name_id"
        }

        public init(
            id: String,
            coords: [String: Double],
            axisIndices: [Int],
            axisValues: [Double],
            name: String,
            elidable: Bool,
            olderSibling: Bool = false,
            nameID: Int? = nil
        ) {
            self.id = id
            self.coords = coords
            self.axisIndices = axisIndices
            self.axisValues = axisValues
            self.name = name
            self.elidable = elidable
            self.olderSibling = olderSibling
            self.nameID = nameID
        }
    }

    public struct ExistingInstance: Codable, Equatable, Sendable {
        public var key: String
        public var composedName: String
        public var coords: [String: Double]
        public var subfamilyNameID: Int
        public var postscriptNameID: Int

        enum CodingKeys: String, CodingKey {
            case key
            case composedName = "composed_name"
            case coords
            case subfamilyNameID = "subfamily_name_id"
            case postscriptNameID = "postscript_name_id"
        }
    }

    public struct InstancesMeta: Codable, Equatable, Sendable {
        public var total: Int
        public var sampleCount: Int

        enum CodingKeys: String, CodingKey {
            case total
            case sampleCount = "sample_count"
        }
    }

    public struct NameAudit: Codable, Equatable, Sendable {
        public var freeStart: Int
        public var used: [NameIDUse]
        public var elidedFallbackID: Int?
        public var elidedFallbackName: String?

        enum CodingKeys: String, CodingKey {
            case freeStart = "free_start"
            case used
            case elidedFallbackID = "elided_fallback_id"
            case elidedFallbackName = "elided_fallback_name"
        }

        public struct NameIDUse: Codable, Equatable, Sendable {
            public var id: Int
            public var description: String
            /// Resolved name-table string when available.
            public var string: String?
            public var protected: Bool?

            public init(id: Int, description: String, string: String? = nil, protected: Bool? = nil) {
                self.id = id
                self.description = description
                self.string = string
                self.protected = protected
            }
        }
    }

    public struct InferredAnalysis: Codable, Equatable, Sendable {
        public var isItalicFont: Bool
        public var gridAxisTags: [String]
        public var namingOrderSuggested: [String]
        /// post.italicAngle when present (counter-clockwise degrees; matches slnt scale).
        public var postItalicAngle: Double?

        enum CodingKeys: String, CodingKey {
            case isItalicFont = "is_italic_font"
            case gridAxisTags = "grid_axis_tags"
            case namingOrderSuggested = "naming_order_suggested"
            case postItalicAngle = "post_italic_angle"
        }
    }

    public init(
        schemaVersion: Int,
        source: SourceInfo,
        readiness: Readiness,
        axes: [AnalyzedAxis],
        statValues: [StatValueRecord],
        compoundStatValues: [CompoundStatRecord] = [],
        instancesExisting: [ExistingInstance],
        instancesExistingMeta: InstancesMeta? = nil,
        nameAudit: NameAudit,
        inferred: InferredAnalysis,
        designAxisTags: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.readiness = readiness
        self.axes = axes
        self.statValues = statValues
        self.compoundStatValues = compoundStatValues
        self.instancesExisting = instancesExisting
        self.instancesExistingMeta = instancesExistingMeta
        self.nameAudit = nameAudit
        self.inferred = inferred
        self.designAxisTags = designAxisTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        source = try c.decode(SourceInfo.self, forKey: .source)
        readiness = try c.decode(Readiness.self, forKey: .readiness)
        axes = try c.decode([AnalyzedAxis].self, forKey: .axes)
        statValues = try c.decode([StatValueRecord].self, forKey: .statValues)
        compoundStatValues = try c.decodeIfPresent([CompoundStatRecord].self, forKey: .compoundStatValues) ?? []
        instancesExisting = try c.decode([ExistingInstance].self, forKey: .instancesExisting)
        instancesExistingMeta = try c.decodeIfPresent(InstancesMeta.self, forKey: .instancesExistingMeta)
        nameAudit = try c.decode(NameAudit.self, forKey: .nameAudit)
        inferred = try c.decode(InferredAnalysis.self, forKey: .inferred)
        designAxisTags = try c.decodeIfPresent([String].self, forKey: .designAxisTags) ?? []
    }
}

// MARK: - ProjectDocument

public enum CoordinateDisplayMode: String, Codable, Sendable, CaseIterable {
    case native
    case reference
}

public struct ProjectDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var created: Date?
    public var modified: Date?
    public var familyLabel: String
    /// User-visible project tab label; falls back to familyLabel then first filename.
    public var displayName: String?
    public var naming: NamingPolicy
    public var template: ProjectTemplate
    public var fonts: [FontDocument]
    public var coordinateDisplay: CoordinateDisplayMode
    /// Project-wide OpenType feature label nameID strategy for save/commit.
    public var nameidStrategy: NameIDStrategy

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case created, modified
        case familyLabel = "family_label"
        case displayName = "display_name"
        case naming, template, fonts
        case coordinateDisplay = "coordinate_display"
        case nameidStrategy = "nameid_strategy"
    }

    public init(
        schemaVersion: Int,
        created: Date? = nil,
        modified: Date? = nil,
        familyLabel: String,
        displayName: String? = nil,
        naming: NamingPolicy,
        template: ProjectTemplate,
        fonts: [FontDocument],
        coordinateDisplay: CoordinateDisplayMode = .reference,
        nameidStrategy: NameIDStrategy = .preserve
    ) {
        self.schemaVersion = schemaVersion
        self.created = created
        self.modified = modified
        self.familyLabel = familyLabel
        self.displayName = displayName
        self.naming = naming
        self.template = template
        self.fonts = fonts
        self.coordinateDisplay = coordinateDisplay
        self.nameidStrategy = nameidStrategy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        created = try c.decodeIfPresent(Date.self, forKey: .created)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified)
        familyLabel = try c.decode(String.self, forKey: .familyLabel)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        naming = try c.decode(NamingPolicy.self, forKey: .naming)
        template = try c.decode(ProjectTemplate.self, forKey: .template)
        fonts = try c.decode([FontDocument].self, forKey: .fonts)
        coordinateDisplay = try c.decodeIfPresent(CoordinateDisplayMode.self, forKey: .coordinateDisplay) ?? .reference
        nameidStrategy = try c.decodeIfPresent(NameIDStrategy.self, forKey: .nameidStrategy)
            ?? fonts.first?.options.nameidStrategy
            ?? .preserve
        migrateFileRolesIfNeeded()
        syncNameIDStrategyToFonts()
    }

    /// Keep per-font commit options aligned with the project preference.
    public mutating func syncNameIDStrategyToFonts() {
        for index in fonts.indices where fonts[index].options.nameidStrategy != nameidStrategy {
            fonts[index].options.nameidStrategy = nameidStrategy
        }
    }

    /// First font is master; others are variants when `file_role` was absent (legacy projects).
    private mutating func migrateFileRolesIfNeeded() {
        guard !fonts.isEmpty else { return }
        let needsMigration = fonts.contains { $0.fileRole == nil }
        guard needsMigration else { return }

        let masterID = fonts[0].id
        for index in fonts.indices {
            if fonts[index].fileRole == nil {
                fonts[index].fileRole = index == 0
                    ? .master()
                    : .variant(masterFontID: masterID)
            }
        }
    }

    /// Font to focus when opening a project — master when present, otherwise first file.
    public var preferredSelectedFontID: String? {
        fonts.first { $0.fileRole?.kind == .master }?.id ?? fonts.first?.id
    }
}

public struct ProjectTemplate: Codable, Equatable, Sendable {
    public var syncRoles: Bool
    public var axes: [AxisDefinition]

    enum CodingKeys: String, CodingKey {
        case syncRoles = "sync_roles"
        case axes
    }

    public init(syncRoles: Bool = true, axes: [AxisDefinition] = []) {
        self.syncRoles = syncRoles
        self.axes = axes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncRoles = try c.decodeIfPresent(Bool.self, forKey: .syncRoles) ?? true
        axes = try c.decodeIfPresent([AxisDefinition].self, forKey: .axes) ?? []
    }
}

public struct FontDocument: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var sourcePath: String
    public var outputPath: String?
    public var analysisSnapshotID: String?
    public var dirty: Bool
    public var fileRole: FileRole?
    public var axes: [AxisDefinition]
    public var options: CommitOptions
    public var includedInstanceKeys: [String]
    public var excludedInstanceKeys: [String]
    public var overrides: InstanceOverrides
    /// Per-file resolved values on registration (`design_record_only`) axes.
    public var fileStatRegistration: [String: Double]
    /// Import-time italic file cue for registration warnings without re-analyzing.
    public var inferredIsItalicFile: Bool?
    /// User-acknowledged plan issues (orphan F3 kept, etc.) — keys from `PlanIssueCodes.issueKey`.
    public var dismissedPlanIssues: [String]
    /// Preserved STAT format 4 compound entries (read-only in Phase 0).
    public var compoundStatValues: [CompoundStatValue]
    /// STAT DesignAxisRecord tags captured at import (fvar parity checks).
    public var statDesignAxisTags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case sourcePath = "source_path"
        case outputPath = "output_path"
        case analysisSnapshotID = "analysis_snapshot_id"
        case dirty
        case fileRole = "file_role"
        case axes, options
        case includedInstanceKeys = "included_instance_keys"
        case excludedInstanceKeys = "excluded_instance_keys"
        case overrides
        case fileStatRegistration = "file_stat_registration"
        case inferredIsItalicFile = "inferred_is_italic_file"
        case dismissedPlanIssues = "dismissed_plan_issues"
        case compoundStatValues = "compound_stat_values"
        case statDesignAxisTags = "stat_design_axis_tags"
    }

    public init(
        id: String,
        sourcePath: String,
        outputPath: String? = nil,
        analysisSnapshotID: String? = nil,
        dirty: Bool = false,
        fileRole: FileRole? = nil,
        axes: [AxisDefinition] = [],
        options: CommitOptions = CommitOptions(),
        includedInstanceKeys: [String] = [],
        excludedInstanceKeys: [String] = [],
        overrides: InstanceOverrides = InstanceOverrides(),
        fileStatRegistration: [String: Double] = [:],
        inferredIsItalicFile: Bool? = nil,
        dismissedPlanIssues: [String] = [],
        compoundStatValues: [CompoundStatValue] = [],
        statDesignAxisTags: [String] = []
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.analysisSnapshotID = analysisSnapshotID
        self.dirty = dirty
        self.fileRole = fileRole
        self.axes = axes
        self.options = options
        self.includedInstanceKeys = includedInstanceKeys
        self.excludedInstanceKeys = excludedInstanceKeys
        self.overrides = overrides
        self.fileStatRegistration = fileStatRegistration
        self.inferredIsItalicFile = inferredIsItalicFile
        self.dismissedPlanIssues = dismissedPlanIssues
        self.compoundStatValues = compoundStatValues
        self.statDesignAxisTags = statDesignAxisTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        outputPath = try c.decodeIfPresent(String.self, forKey: .outputPath)
        analysisSnapshotID = try c.decodeIfPresent(String.self, forKey: .analysisSnapshotID)
        dirty = try c.decodeIfPresent(Bool.self, forKey: .dirty) ?? false
        fileRole = try c.decodeIfPresent(FileRole.self, forKey: .fileRole)
        axes = try c.decodeIfPresent([AxisDefinition].self, forKey: .axes) ?? []
        options = try c.decodeIfPresent(CommitOptions.self, forKey: .options) ?? CommitOptions()
        includedInstanceKeys = try c.decodeIfPresent([String].self, forKey: .includedInstanceKeys) ?? []
        excludedInstanceKeys = try c.decodeIfPresent([String].self, forKey: .excludedInstanceKeys) ?? []
        overrides = try c.decodeIfPresent(InstanceOverrides.self, forKey: .overrides) ?? InstanceOverrides()
        fileStatRegistration = try c.decodeIfPresent([String: Double].self, forKey: .fileStatRegistration) ?? [:]
        inferredIsItalicFile = try c.decodeIfPresent(Bool.self, forKey: .inferredIsItalicFile)
        dismissedPlanIssues = try c.decodeIfPresent([String].self, forKey: .dismissedPlanIssues) ?? []
        compoundStatValues = try c.decodeIfPresent([CompoundStatValue].self, forKey: .compoundStatValues) ?? []
        statDesignAxisTags = try c.decodeIfPresent([String].self, forKey: .statDesignAxisTags) ?? []
    }
}

public struct InstanceOverrides: Codable, Equatable, Sendable {
    public var perInstance: [PerInstanceOverride]

    enum CodingKeys: String, CodingKey {
        case perInstance = "per_instance"
    }

    public init(perInstance: [PerInstanceOverride] = []) {
        self.perInstance = perInstance
    }
}

public struct PerInstanceOverride: Codable, Equatable, Sendable {
    public var key: String
    public var omitAxesFromName: [String]?
    public var pinCoords: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case key
        case omitAxesFromName = "omit_axes_from_name"
        case pinCoords = "pin_coords"
    }
}

// MARK: - InstancePlan

public struct InstancePlan: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var fontID: String
    public var formula: PlanFormula
    public var instances: [PlannedInstance]
    public var warnings: [PlanWarning]
    public var namePlanSummary: NamePlanSummary?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fontID = "font_id"
        case formula, instances, warnings
        case namePlanSummary = "name_plan_summary"
    }
}

public struct PlanFormula: Codable, Equatable, Sendable {
    public var parts: [Int]
    public var totalGenerated: Int
    public var totalIncluded: Int
    public var totalExcluded: Int

    enum CodingKeys: String, CodingKey {
        case parts
        case totalGenerated = "total_generated"
        case totalIncluded = "total_included"
        case totalExcluded = "total_excluded"
    }
}

public struct PlannedInstance: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var composedName: String
    public var coords: [String: Double]
    public var included: Bool
    public var duplicate: Bool
    public var namingChain: [NamingChainLink]

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key
        case composedName = "composed_name"
        case coords, included, duplicate
        case namingChain = "naming_chain"
    }
}

public struct NamingChainLink: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case axis
        case registration
        case clarifier
    }

    public var kind: Kind
    public var tag: String
    public var name: String
    public var elided: Bool

    enum CodingKeys: String, CodingKey {
        case kind, tag, name, elided
    }

    public init(kind: Kind = .axis, tag: String, name: String, elided: Bool) {
        self.kind = kind
        self.tag = tag
        self.name = name
        self.elided = elided
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .axis
        tag = try c.decode(String.self, forKey: .tag)
        name = try c.decode(String.self, forKey: .name)
        elided = try c.decodeIfPresent(Bool.self, forKey: .elided) ?? false
    }
}

public struct PlanWarning: Codable, Equatable, Sendable {
    public var code: String
    public var axis: String?
    public var name: String?
    public var keys: [String]?
    /// Axis stop IDs involved in this warning (for axis-tree navigation).
    public var stopIDs: [String]?
    public var message: String
    /// Short guidance on how to resolve the warning in the axis tree.
    public var hint: String?

    public init(
        code: String,
        axis: String? = nil,
        name: String? = nil,
        keys: [String]? = nil,
        stopIDs: [String]? = nil,
        message: String,
        hint: String? = nil
    ) {
        self.code = code
        self.axis = axis
        self.name = name
        self.keys = keys
        self.stopIDs = stopIDs
        self.message = message
        self.hint = hint
    }
}

public struct NamePlanSummary: Codable, Equatable, Sendable {
    public var familyPSPrefix: String?
    public var newIDRange: [Int]?
    public var instanceCount: Int?
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case familyPSPrefix = "family_ps_prefix"
        case newIDRange = "new_id_range"
        case instanceCount = "instance_count"
        case note
    }
}

// MARK: - Commit

public struct CommitRequest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: String
    public var sourcePath: String
    public var outputPath: String
    public var dryRun: Bool
    public var options: CommitOptions
    public var naming: NamingPolicy
    public var fileRole: FileRole?
    public var axes: [AxisDefinition]
    public var includedInstanceKeys: [String]
    public var fileStatRegistration: [String: Double]
    public var compoundStatValues: [CompoundStatValue]
    public var originalSourcePath: String?
    public var allowInPlace: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case sourcePath = "source_path"
        case outputPath = "output_path"
        case dryRun = "dry_run"
        case options, naming
        case fileRole = "file_role"
        case axes
        case includedInstanceKeys = "included_instance_keys"
        case fileStatRegistration = "file_stat_registration"
        case compoundStatValues = "compound_stat_values"
        case originalSourcePath = "original_source_path"
        case allowInPlace = "allow_in_place"
    }

    public init(
        schemaVersion: Int,
        requestID: String,
        sourcePath: String,
        outputPath: String,
        dryRun: Bool,
        options: CommitOptions,
        naming: NamingPolicy,
        fileRole: FileRole? = nil,
        axes: [AxisDefinition],
        includedInstanceKeys: [String] = [],
        fileStatRegistration: [String: Double] = [:],
        compoundStatValues: [CompoundStatValue] = [],
        originalSourcePath: String? = nil,
        allowInPlace: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.dryRun = dryRun
        self.options = options
        self.naming = naming
        self.fileRole = fileRole
        self.axes = axes
        self.includedInstanceKeys = includedInstanceKeys
        self.fileStatRegistration = fileStatRegistration
        self.compoundStatValues = compoundStatValues
        self.originalSourcePath = originalSourcePath
        self.allowInPlace = allowInPlace
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        requestID = try c.decode(String.self, forKey: .requestID)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        outputPath = try c.decode(String.self, forKey: .outputPath)
        dryRun = try c.decode(Bool.self, forKey: .dryRun)
        options = try c.decode(CommitOptions.self, forKey: .options)
        naming = try c.decode(NamingPolicy.self, forKey: .naming)
        fileRole = try c.decodeIfPresent(FileRole.self, forKey: .fileRole)
        axes = try c.decode([AxisDefinition].self, forKey: .axes)
        includedInstanceKeys = try c.decodeIfPresent([String].self, forKey: .includedInstanceKeys) ?? []
        fileStatRegistration = try c.decodeIfPresent([String: Double].self, forKey: .fileStatRegistration) ?? [:]
        compoundStatValues = try c.decodeIfPresent([CompoundStatValue].self, forKey: .compoundStatValues) ?? []
        originalSourcePath = try c.decodeIfPresent(String.self, forKey: .originalSourcePath)
        allowInPlace = try c.decodeIfPresent(Bool.self, forKey: .allowInPlace) ?? false
    }
}

public struct CommitResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var requestID: String
    public var ok: Bool
    public var outputPath: String?
    public var dryRun: Bool
    public var summary: CommitSummary?
    public var diff: CommitDiff?
    public var validation: CommitValidation?
    public var warnings: [PlanWarning]
    public var errors: [CommitError]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case ok
        case outputPath = "output_path"
        case dryRun = "dry_run"
        case summary, diff, validation, warnings, errors
    }
}

public struct CommitValidation: Codable, Equatable, Sendable {
    public var ok: Bool
    public var issueCount: Int
    public var issues: [CommitValidationIssue]

    enum CodingKeys: String, CodingKey {
        case ok
        case issueCount = "issue_count"
        case issues
    }
}

public struct CommitValidationIssue: Codable, Equatable, Sendable {
    public var code: String
    public var severity: String
    public var message: String
}

public struct CommitDiffOTReflowEntry: Codable, Equatable, Sendable {
    public var fromID: Int
    public var toID: Int
    public var string: String?
    public var feature: String?

    enum CodingKeys: String, CodingKey {
        case fromID = "from"
        case toID = "to"
        case string
        case feature
    }
}

public struct CommitDiff: Codable, Equatable, Sendable {
    public var familyPSPrefix: String?
    public var elidedFallbackName: String?
    public var elidedFallbackID: Int?
    public var nameIDRange: [Int]?
    public var nameRecordsPlanned: [CommitNameRecordPlanned]
    /// Write-order name records (axis → stat → elided → instances). Prefer for Save Review sequencing.
    public var nameRecordsSequenced: [CommitNameRecordPlanned]
    public var statValuesPlanned: [CommitDiffStatValuePlanned]
    public var instancesPlanned: [CommitDiffInstancePlanned]
    public var otReflowMapping: [CommitDiffOTReflowEntry]?

    enum CodingKeys: String, CodingKey {
        case familyPSPrefix = "family_ps_prefix"
        case elidedFallbackName = "elided_fallback_name"
        case elidedFallbackID = "elided_fallback_id"
        case nameIDRange = "name_id_range"
        case nameRecordsPlanned = "name_records_planned"
        case nameRecordsSequenced = "name_records_sequenced"
        case statValuesPlanned = "stat_values_planned"
        case instancesPlanned = "instances_planned"
        case otReflowMapping = "ot_reflow_mapping"
    }

    public init(
        familyPSPrefix: String? = nil,
        elidedFallbackName: String? = nil,
        elidedFallbackID: Int? = nil,
        nameIDRange: [Int]? = nil,
        nameRecordsPlanned: [CommitNameRecordPlanned] = [],
        nameRecordsSequenced: [CommitNameRecordPlanned] = [],
        statValuesPlanned: [CommitDiffStatValuePlanned] = [],
        instancesPlanned: [CommitDiffInstancePlanned] = [],
        otReflowMapping: [CommitDiffOTReflowEntry]? = nil
    ) {
        self.familyPSPrefix = familyPSPrefix
        self.elidedFallbackName = elidedFallbackName
        self.elidedFallbackID = elidedFallbackID
        self.nameIDRange = nameIDRange
        self.nameRecordsPlanned = nameRecordsPlanned
        self.nameRecordsSequenced = nameRecordsSequenced.isEmpty ? nameRecordsPlanned : nameRecordsSequenced
        self.statValuesPlanned = statValuesPlanned
        self.instancesPlanned = instancesPlanned
        self.otReflowMapping = otReflowMapping
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        familyPSPrefix = try c.decodeIfPresent(String.self, forKey: .familyPSPrefix)
        elidedFallbackName = try c.decodeIfPresent(String.self, forKey: .elidedFallbackName)
        elidedFallbackID = try c.decodeIfPresent(Int.self, forKey: .elidedFallbackID)
        nameIDRange = try c.decodeIfPresent([Int].self, forKey: .nameIDRange)
        nameRecordsPlanned = try c.decodeIfPresent([CommitNameRecordPlanned].self, forKey: .nameRecordsPlanned) ?? []
        nameRecordsSequenced = try c.decodeIfPresent([CommitNameRecordPlanned].self, forKey: .nameRecordsSequenced)
            ?? nameRecordsPlanned
        statValuesPlanned = try c.decodeIfPresent([CommitDiffStatValuePlanned].self, forKey: .statValuesPlanned) ?? []
        instancesPlanned = try c.decodeIfPresent([CommitDiffInstancePlanned].self, forKey: .instancesPlanned) ?? []
        otReflowMapping = try c.decodeIfPresent([CommitDiffOTReflowEntry].self, forKey: .otReflowMapping)
    }
}

public struct CommitNameRecordPlanned: Codable, Equatable, Sendable {
    public var id: Int
    public var string: String
    public var role: String
}

public struct CommitDiffStatValuePlanned: Codable, Equatable, Sendable {
    public var tag: String
    public var value: Double
    public var name: String
    public var elidable: Bool
    public var statFormat: Int
    public var nameID: Int?
    public var linkedValue: Double?
    public var rangeMin: Double?
    public var rangeMax: Double?

    enum CodingKeys: String, CodingKey {
        case tag, value, name, elidable
        case statFormat = "stat_format"
        case nameID = "name_id"
        case linkedValue = "linked_value"
        case rangeMin = "range_min"
        case rangeMax = "range_max"
    }
}

public struct CommitDiffInstancePlanned: Codable, Equatable, Sendable {
    public var composedName: String
    public var subfamilyNameID: Int
    public var postscriptName: String?
    public var postscriptNameID: Int?

    enum CodingKeys: String, CodingKey {
        case composedName = "composed_name"
        case subfamilyNameID = "subfamily_name_id"
        case postscriptName = "postscript_name"
        case postscriptNameID = "postscript_name_id"
    }
}

public enum CommitDiffChangeKind: String, Codable, Equatable, Sendable {
    case added
    case removed
    case changed
    case unchanged
}

public struct CommitDiffStatRow: Codable, Equatable, Sendable, Identifiable {
    public var tag: String
    public var value: Double
    public var beforeName: String?
    public var afterName: String?
    public var beforeNameID: Int?
    public var afterNameID: Int?
    public var afterStatFormat: Int?
    public var afterLinkedValue: Double?
    public var change: CommitDiffChangeKind

    public var id: String { "\(tag):\(value)" }

    enum CodingKeys: String, CodingKey {
        case tag, value, beforeName, afterName, beforeNameID, afterNameID, change
        case afterStatFormat = "after_stat_format"
        case afterLinkedValue = "after_linked_value"
    }
}

public struct CommitDiffInstanceRow: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var beforeName: String?
    public var afterName: String?
    public var beforePostscriptName: String?
    public var afterPostscriptName: String?
    public var coords: [String: Double]?
    public var change: CommitDiffChangeKind
    public var postscriptChange: CommitDiffChangeKind

    public var id: String { key }

    public init(
        key: String,
        beforeName: String? = nil,
        afterName: String? = nil,
        beforePostscriptName: String? = nil,
        afterPostscriptName: String? = nil,
        coords: [String: Double]? = nil,
        change: CommitDiffChangeKind,
        postscriptChange: CommitDiffChangeKind = .unchanged
    ) {
        self.key = key
        self.beforeName = beforeName
        self.afterName = afterName
        self.beforePostscriptName = beforePostscriptName
        self.afterPostscriptName = afterPostscriptName
        self.coords = coords
        self.change = change
        self.postscriptChange = postscriptChange
    }
}

public struct CommitDiffNameIDRow: Codable, Equatable, Sendable, Identifiable {
    /// Name table slot (≥256).
    public var id: Int
    public var beforeDescription: String?
    public var beforeString: String?
    public var afterString: String?
    public var afterRole: String?
    public var change: CommitDiffChangeKind
    /// Prior slot when the same string moved to this name ID.
    public var reflowedFromNameID: Int?
    /// Hidden from Save Review when consumed as reflow source/target pair.
    public var reflowSuppressed: Bool

    public init(
        id: Int,
        beforeDescription: String? = nil,
        beforeString: String? = nil,
        afterString: String? = nil,
        afterRole: String? = nil,
        change: CommitDiffChangeKind,
        reflowedFromNameID: Int? = nil,
        reflowSuppressed: Bool = false
    ) {
        self.id = id
        self.beforeDescription = beforeDescription
        self.beforeString = beforeString
        self.afterString = afterString
        self.afterRole = afterRole
        self.change = change
        self.reflowedFromNameID = reflowedFromNameID
        self.reflowSuppressed = reflowSuppressed
    }

    enum CodingKeys: String, CodingKey {
        case id, beforeDescription, beforeString, afterString, afterRole, change
        case reflowedFromNameID = "reflowed_from_name_id"
        case reflowSuppressed = "reflow_suppressed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        beforeDescription = try c.decodeIfPresent(String.self, forKey: .beforeDescription)
        beforeString = try c.decodeIfPresent(String.self, forKey: .beforeString)
        afterString = try c.decodeIfPresent(String.self, forKey: .afterString)
        afterRole = try c.decodeIfPresent(String.self, forKey: .afterRole)
        change = try c.decode(CommitDiffChangeKind.self, forKey: .change)
        reflowedFromNameID = try c.decodeIfPresent(Int.self, forKey: .reflowedFromNameID)
        reflowSuppressed = try c.decodeIfPresent(Bool.self, forKey: .reflowSuppressed) ?? false
    }
}

public struct CommitDiffReport: Codable, Equatable, Sendable {
    public var statRows: [CommitDiffStatRow]
    public var instanceRows: [CommitDiffInstanceRow]
    public var nameIDRows: [CommitDiffNameIDRow]

    public var statChangedCount: Int {
        statRows.filter { $0.change != .unchanged }.count
    }

    public var instanceChangedCount: Int {
        instanceRows.filter { $0.change != .unchanged }.count
    }

    public var nameIDChangedCount: Int {
        nameIDRows.filter { $0.change != .unchanged }.count
    }
}

public struct CommitSummary: Codable, Equatable, Sendable {
    public var instancesWritten: Int
    public var statValuesWritten: Int
    public var nameIDsAllocated: [Int]
    public var wipedInstanceCount: Int
    public var protectedNameIDs: [Int]
    public var otReflowMapping: [String: Int]?
    public var orphanNameIDsDropped: [Int]?

    enum CodingKeys: String, CodingKey {
        case instancesWritten = "instances_written"
        case statValuesWritten = "stat_values_written"
        case nameIDsAllocated = "name_ids_allocated"
        case wipedInstanceCount = "wiped_instance_count"
        case protectedNameIDs = "protected_name_ids"
        case otReflowMapping = "ot_reflow_mapping"
        case orphanNameIDsDropped = "orphan_nameids_dropped"
    }

    public init(
        instancesWritten: Int = 0,
        statValuesWritten: Int = 0,
        nameIDsAllocated: [Int] = [],
        wipedInstanceCount: Int = 0,
        protectedNameIDs: [Int] = [],
        otReflowMapping: [String: Int]? = nil,
        orphanNameIDsDropped: [Int]? = nil
    ) {
        self.instancesWritten = instancesWritten
        self.statValuesWritten = statValuesWritten
        self.nameIDsAllocated = nameIDsAllocated
        self.wipedInstanceCount = wipedInstanceCount
        self.protectedNameIDs = protectedNameIDs
        self.otReflowMapping = otReflowMapping
        self.orphanNameIDsDropped = orphanNameIDsDropped
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instancesWritten = try c.decode(Int.self, forKey: .instancesWritten)
        statValuesWritten = try c.decode(Int.self, forKey: .statValuesWritten)
        nameIDsAllocated = try c.decode([Int].self, forKey: .nameIDsAllocated)
        wipedInstanceCount = try c.decode(Int.self, forKey: .wipedInstanceCount)
        protectedNameIDs = try c.decode([Int].self, forKey: .protectedNameIDs)
        otReflowMapping = try c.decodeIfPresent([String: Int].self, forKey: .otReflowMapping)
        orphanNameIDsDropped = try c.decodeIfPresent([Int].self, forKey: .orphanNameIDsDropped)
    }
}

public struct CommitError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
}
