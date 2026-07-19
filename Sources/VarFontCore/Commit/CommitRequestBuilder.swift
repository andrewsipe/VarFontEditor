import Foundation

/// Builds save payloads for vfcommit from live project state.
public enum CommitRequestBuilder {
    public static func make(
        font: FontDocument,
        naming: NamingPolicy,
        plan: InstancePlan,
        outputPath: String,
        dryRun: Bool,
        nameidStrategy: NameIDStrategy? = nil,
        windowsNameTable: [WindowsNameRecord] = []
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
            axes: font.axes,
            includedInstanceKeys: includedInstanceKeys(font: font, plan: plan),
            fileStatRegistration: font.fileStatRegistration,
            compoundStatValues: font.compoundStatValues,
            statDesignAxisTags: resolvedDesignAxisTags(for: font),
            windowsNamePatches: WindowsNameTableEditing.commitPatches(
                windowsNameTable: windowsNameTable,
                overrides: font.windowsNameOverrides
            )
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

    /// Folder for Export All: if writing into `chosenDirectory` with original basenames would
    /// overwrite any source file, nest under `{folderLabel} Patched` (or `Patched`).
    public static func packageExportDirectory(
        chosenDirectory: URL,
        sourcePaths: [String],
        folderLabel: String?
    ) -> (directory: URL, nestedBecauseOfCollision: Bool) {
        let wouldCollide = sourcePaths.contains { source in
            let package = URL(fileURLWithPath: packageOutputPath(for: source, in: chosenDirectory))
            return package.standardizedFileURL == URL(fileURLWithPath: source).standardizedFileURL
        }
        guard wouldCollide else {
            return (chosenDirectory, false)
        }
        let base = folderLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let nestedName: String = {
            if let base, !base.isEmpty {
                return base.hasSuffix(" Patched") ? base : "\(base) Patched"
            }
            return "Patched"
        }()
        return (chosenDirectory.appendingPathComponent(nestedName, isDirectory: true), true)
    }

    public static func orderedAxes(_ axes: [AxisDefinition], naming: NamingPolicy) -> [AxisDefinition] {
        axes
    }

    public static func resolvedDesignAxisTags(for font: FontDocument) -> [String] {
        let fromAxes = font.axes.map(\.tag)
        if !fromAxes.isEmpty { return fromAxes }
        if !font.statDesignAxisTags.isEmpty { return font.statDesignAxisTags }
        return []
    }

    public static func resolvedFvarAxisTags(for font: FontDocument) -> [String] {
        AxisOrderRealigner.fvarTagOrder(
            from: font.axes.map(\.tag),
            axes: font.axes
        )
    }

    /// Always emit the live plan's included keys so vfcommit never treats an empty
    /// list as “entire axis cartesian product” (which can explode on multi-axis fonts
    /// even when the UI only shows a handful of instances).
    public static func includedInstanceKeys(font: FontDocument, plan: InstancePlan) -> [String] {
        if !font.includedInstanceKeys.isEmpty {
            return font.includedInstanceKeys
        }
        return plan.instances.filter(\.included).map(\.key)
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

    /// Pass-through commit options. STAT DesignAxisRecord order may be rewritten on
    /// save; fvar axis record order and scales are not.
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
