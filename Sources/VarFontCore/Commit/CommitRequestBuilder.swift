import Foundation

/// Builds save payloads for vfcommit from live project state.
public enum CommitRequestBuilder {
    public static func make(
        font: FontDocument,
        naming: NamingPolicy,
        plan: InstancePlan,
        outputPath: String,
        dryRun: Bool,
        nameidStrategy: NameIDStrategy? = nil
    ) -> CommitRequest {
        CommitRequest(
            schemaVersion: 1,
            requestID: UUID().uuidString.lowercased(),
            sourcePath: font.sourcePath,
            outputPath: outputPath,
            dryRun: dryRun,
            options: commitOptions(from: font.options, nameidStrategy: nameidStrategy),
            naming: namingForCommit(naming, axisTags: font.axes.map(\.tag), font: font),
            fileRole: font.fileRole,
            axes: orderedAxes(font.axes, naming: naming),
            includedInstanceKeys: includedInstanceKeys(font: font, plan: plan),
            fileStatRegistration: font.fileStatRegistration,
            compoundStatValues: font.compoundStatValues
        )
    }

    public static func suggestedOutputPath(for sourcePath: String) -> String {
        let source = URL(fileURLWithPath: sourcePath)
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let suffix = ext.isEmpty ? "\(stem)-patched" : "\(stem)-patched.\(ext)"
        return source.deletingLastPathComponent().appendingPathComponent(suffix).path
    }

    /// Package export path: original basename inside a chosen folder (no `-patched` suffix).
    public static func packageOutputPath(for sourcePath: String, in directory: URL) -> String {
        let name = URL(fileURLWithPath: sourcePath).lastPathComponent
        return directory.appendingPathComponent(name).path
    }

    public static func orderedAxes(_ axes: [AxisDefinition], naming: NamingPolicy) -> [AxisDefinition] {
        let byTag = Dictionary(uniqueKeysWithValues: axes.map { ($0.tag, $0) })
        var ordered: [AxisDefinition] = []
        for tag in naming.order {
            if let axis = byTag[tag] {
                ordered.append(axis)
            }
        }
        for axis in axes where !naming.order.contains(axis.tag) {
            ordered.append(axis)
        }
        return ordered
    }

    public static func includedInstanceKeys(font: FontDocument, plan: InstancePlan) -> [String] {
        if !font.includedInstanceKeys.isEmpty {
            return font.includedInstanceKeys
        }
        if !font.excludedInstanceKeys.isEmpty {
            return plan.instances.filter(\.included).map(\.key)
        }
        return []
    }

    private static func namingForCommit(_ naming: NamingPolicy, axisTags: [String], font: FontDocument) -> NamingPolicy {
        let resolved = ElidedFallbackResolver.resolve(
            axes: font.axes,
            namingOrder: NamingPolicy.mergedOrder(projectOrder: naming.order, axisTags: axisTags),
            fileStatRegistration: font.fileStatRegistration,
            sourceElidedFallback: naming.elidedFallback,
            fileRole: font.fileRole
        )
        return NamingPolicy(
            order: NamingPolicy.mergedOrder(projectOrder: naming.order, axisTags: axisTags),
            elidedFallback: resolved.value
        )
    }

    /// Pass-through commit options. fvar axis records are never rewritten on save.
    private static func commitOptions(
        from options: CommitOptions,
        nameidStrategy: NameIDStrategy? = nil
    ) -> CommitOptions {
        guard let nameidStrategy else { return options }
        var merged = options
        merged.nameidStrategy = nameidStrategy
        return merged
    }
}
