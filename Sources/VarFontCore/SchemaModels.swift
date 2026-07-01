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
    public var statFormat: Int
    public var rangeMin: Double?
    public var rangeMax: Double?
    public var linkedValue: Double?

    enum CodingKeys: String, CodingKey {
        case id, value, name, elidable
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
        statFormat: Int = 1,
        rangeMin: Double? = nil,
        rangeMax: Double? = nil,
        linkedValue: Double? = nil
    ) {
        self.id = id
        self.value = value
        self.name = name
        self.elidable = elidable
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
        statFormat = try c.decodeIfPresent(Int.self, forKey: .statFormat) ?? 1
        rangeMin = try c.decodeIfPresent(Double.self, forKey: .rangeMin)
        rangeMax = try c.decodeIfPresent(Double.self, forKey: .rangeMax)
        linkedValue = try c.decodeIfPresent(Double.self, forKey: .linkedValue)
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

    public var id: String { tag }

    enum CodingKeys: String, CodingKey {
        case tag
        case displayName = "display_name"
        case min, `default`, max, role
        case roleInferred = "role_inferred"
        case values
    }

    public init(
        tag: String,
        displayName: String? = nil,
        min: Double? = nil,
        default: Double? = nil,
        max: Double? = nil,
        role: AxisRole = .instance,
        roleInferred: AxisRole? = nil,
        values: [AxisValue] = []
    ) {
        self.tag = tag
        self.displayName = displayName
        self.min = min
        self.default = `default`
        self.max = max
        self.role = role
        self.roleInferred = roleInferred
        self.values = values
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
    }

    /// True when this axis exists only in STAT DesignAxisRecord (no fvar scale).
    public var isDesignRecordOnly: Bool { role == .designRecordOnly }

    /// True when fvar min/default/max apply to this axis.
    public var hasFvarScale: Bool { !isDesignRecordOnly }
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
        var result = axisOrder.filter { !NamingToken.isClarifier($0) }
        for token in defaultClarifierTokens where !result.contains(token) {
            result.append(token)
        }
        return result
    }

    /// Project naming order filtered to axes present in this file plus clarifier tokens.
    public static func mergedOrder(projectOrder: [String], axisTags: [String]) -> [String] {
        var result: [String] = []
        var seenAxes = Set<String>()
        var seenClarifiers = Set<String>()

        for token in projectOrder {
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
        return result
    }
}

public enum NamingToken {
    public static func isClarifier(_ token: String) -> Bool {
        token.hasPrefix("@")
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

public struct CommitOptions: Codable, Equatable, Sendable {
    public var fixFvarDefault: Bool
    public var allocatePostscriptNames: Bool
    public var preserveStatFormat3: Bool?
    /// nameID 25 — prefix for fvar instance PostScript names (e.g. NouveauLEDVariable).
    public var familyPSPrefix: String?

    enum CodingKeys: String, CodingKey {
        case fixFvarDefault = "fix_fvar_default"
        case allocatePostscriptNames = "allocate_postscript_names"
        case preserveStatFormat3 = "preserve_stat_format_3"
        case familyPSPrefix = "family_ps_prefix"
    }

    public init(
        fixFvarDefault: Bool = false,
        allocatePostscriptNames: Bool = true,
        preserveStatFormat3: Bool? = true,
        familyPSPrefix: String? = nil
    ) {
        self.fixFvarDefault = fixFvarDefault
        self.allocatePostscriptNames = allocatePostscriptNames
        self.preserveStatFormat3 = preserveStatFormat3
        self.familyPSPrefix = familyPSPrefix
    }
}

// MARK: - FontAnalysis

public struct FontAnalysis: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var source: SourceInfo
    public var readiness: Readiness
    public var axes: [AnalyzedAxis]
    public var statValues: [StatValueRecord]
    public var instancesExisting: [ExistingInstance]
    public var instancesExistingMeta: InstancesMeta?
    public var nameAudit: NameAudit
    public var inferred: InferredAnalysis

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source, readiness, axes
        case statValues = "stat_values"
        case instancesExisting = "instances_existing"
        case instancesExistingMeta = "instances_existing_meta"
        case nameAudit = "name_audit"
        case inferred
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

        public var id: String { tag }

        enum CodingKeys: String, CodingKey {
            case tag
            case displayName = "display_name"
            case min, `default`, max, ordering
            case roleInferred = "role_inferred"
            case variesInExistingInstances = "varies_in_existing_instances"
            case valuesExisting = "values_existing"
        }
    }

    public struct StatValueSnapshot: Codable, Equatable, Sendable {
        public var format: Int?
        public var value: Double?
        public var name: String
        public var elidable: Bool?
        public var linkedValue: Double?
        public var rangeMin: Double?
        public var rangeMax: Double?
        public var nominal: Double?

        enum CodingKeys: String, CodingKey {
            case format, value, name, elidable
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
        public var nameID: Int?
        public var value: Double?
        public var linkedValue: Double?
        public var rangeMin: Double?
        public var rangeMax: Double?
        public var nominal: Double?

        enum CodingKeys: String, CodingKey {
            case format, tag, name, elidable
            case nameID = "name_id"
            case value
            case linkedValue = "linked_value"
            case rangeMin = "range_min"
            case rangeMax = "range_max"
            case nominal
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

        enum CodingKeys: String, CodingKey {
            case isItalicFont = "is_italic_font"
            case gridAxisTags = "grid_axis_tags"
            case namingOrderSuggested = "naming_order_suggested"
        }
    }
}

// MARK: - ProjectDocument

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

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case created, modified
        case familyLabel = "family_label"
        case displayName = "display_name"
        case naming, template, fonts
    }

    public init(
        schemaVersion: Int,
        created: Date? = nil,
        modified: Date? = nil,
        familyLabel: String,
        displayName: String? = nil,
        naming: NamingPolicy,
        template: ProjectTemplate,
        fonts: [FontDocument]
    ) {
        self.schemaVersion = schemaVersion
        self.created = created
        self.modified = modified
        self.familyLabel = familyLabel
        self.displayName = displayName
        self.naming = naming
        self.template = template
        self.fonts = fonts
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
        migrateFileRolesIfNeeded()
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
        overrides: InstanceOverrides = InstanceOverrides()
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
    public var warnings: [PlanWarning]
    public var errors: [CommitError]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case ok
        case outputPath = "output_path"
        case dryRun = "dry_run"
        case summary, diff, warnings, errors
    }
}

public struct CommitDiff: Codable, Equatable, Sendable {
    public var familyPSPrefix: String?
    public var elidedFallbackName: String?
    public var elidedFallbackID: Int?
    public var nameIDRange: [Int]?
    public var nameRecordsPlanned: [CommitNameRecordPlanned]
    public var statValuesPlanned: [CommitDiffStatValuePlanned]
    public var instancesPlanned: [CommitDiffInstancePlanned]

    enum CodingKeys: String, CodingKey {
        case familyPSPrefix = "family_ps_prefix"
        case elidedFallbackName = "elided_fallback_name"
        case elidedFallbackID = "elided_fallback_id"
        case nameIDRange = "name_id_range"
        case nameRecordsPlanned = "name_records_planned"
        case statValuesPlanned = "stat_values_planned"
        case instancesPlanned = "instances_planned"
    }

    public init(
        familyPSPrefix: String? = nil,
        elidedFallbackName: String? = nil,
        elidedFallbackID: Int? = nil,
        nameIDRange: [Int]? = nil,
        nameRecordsPlanned: [CommitNameRecordPlanned] = [],
        statValuesPlanned: [CommitDiffStatValuePlanned] = [],
        instancesPlanned: [CommitDiffInstancePlanned] = []
    ) {
        self.familyPSPrefix = familyPSPrefix
        self.elidedFallbackName = elidedFallbackName
        self.elidedFallbackID = elidedFallbackID
        self.nameIDRange = nameIDRange
        self.nameRecordsPlanned = nameRecordsPlanned
        self.statValuesPlanned = statValuesPlanned
        self.instancesPlanned = instancesPlanned
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
    public var coords: [String: Double]?
    public var change: CommitDiffChangeKind

    public var id: String { key }
}

public struct CommitDiffNameIDRow: Codable, Equatable, Sendable, Identifiable {
    /// Name table slot (≥256).
    public var id: Int
    public var beforeDescription: String?
    public var beforeString: String?
    public var afterString: String?
    public var afterRole: String?
    public var change: CommitDiffChangeKind
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

    enum CodingKeys: String, CodingKey {
        case instancesWritten = "instances_written"
        case statValuesWritten = "stat_values_written"
        case nameIDsAllocated = "name_ids_allocated"
        case wipedInstanceCount = "wiped_instance_count"
        case protectedNameIDs = "protected_name_ids"
    }
}

public struct CommitError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
}
