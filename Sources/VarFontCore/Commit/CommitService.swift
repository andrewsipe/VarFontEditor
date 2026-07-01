import Foundation

public enum CommitServiceError: Error, Equatable, Sendable {
    case helperNotFound
    case helperUnavailable(String)
    case helperFailed(String)
    case invalidHelperOutput(String)
}

/// Save-time commit bridge. Shells out to bundled `vfcommit` (Python + vendored FontCore subset).
public struct CommitService: Sendable {
    public var helperURL: URL?
    public var pythonExecutable: String

    public init(helperURL: URL? = nil, pythonExecutable: String? = nil) {
        self.helperURL = helperURL
        self.pythonExecutable = pythonExecutable ?? Self.defaultPythonExecutable()
    }

    /// Prefer Homebrew / usr-local interpreters; GUI apps often lack them on `PATH` for `/usr/bin/env`.
    public static func defaultPythonExecutable() -> String {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if canImportFontTools(using: path) {
                return path
            }
        }
        return "/usr/bin/env"
    }

    private static func canImportFontTools(using pythonPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import fontTools"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Bundled `vfcommit/vfcommit.py`, synced into the app cache. Never reads ~/Documents at launch.
    public static func defaultHelperURL() -> URL? {
        if let bundled = bundledHelperURL(),
           FileManager.default.fileExists(atPath: bundled.path) {
            return installedHelperURL(preferredSource: bundled.deletingLastPathComponent())
        }

        let cached = cacheDirectory().appendingPathComponent("vfcommit.py")
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        #if DEBUG
        let dev = developmentSourceDirectory()
        let devScript = dev.appendingPathComponent("vfcommit.py")
        if FileManager.default.fileExists(atPath: devScript.path) {
            return installedHelperURL(preferredSource: dev)
        }
        #endif

        return nil
    }

    private static func bundledHelperURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("vfcommit/vfcommit.py")
    }

    private static func developmentSourceDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Commit
            .deletingLastPathComponent() // VarFontCore
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // VarFontEditor
            .appendingPathComponent("Tools/vfcommit", isDirectory: true)
    }

    private static func cacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VarFontStudio/vfcommit", isDirectory: true)
    }

    /// Copy vfcommit into the app cache so the Python subprocess only reads container paths.
    private static func installedHelperURL(preferredSource: URL) -> URL? {
        let cacheDir = cacheDirectory()
        let helper = cacheDir.appendingPathComponent("vfcommit.py")
        do {
            try syncHelper(from: preferredSource, to: cacheDir)
            return helper
        } catch {
            return FileManager.default.fileExists(atPath: helper.path) ? helper : nil
        }
    }

    private static func syncHelper(from source: URL, to cache: URL) throws {
        let sourceScript = source.appendingPathComponent("vfcommit.py")
        guard FileManager.default.fileExists(atPath: sourceScript.path) else {
            throw CommitServiceError.helperNotFound
        }

        let cacheScript = cache.appendingPathComponent("vfcommit.py")
        let sourceFingerprint = helperFingerprint(at: source)
        let cacheFingerprint = helperFingerprint(at: cache)
        if FileManager.default.fileExists(atPath: cacheScript.path),
           sourceFingerprint == cacheFingerprint {
            return
        }

        if FileManager.default.fileExists(atPath: cache.path) {
            try FileManager.default.removeItem(at: cache)
        }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: cache)
        removePythonCaches(under: cache)
    }

    /// Fingerprint the helper tree so stale cache copies refresh when vfcommit changes.
    private static func helperFingerprint(at root: URL) -> String {
        let script = root.appendingPathComponent("vfcommit.py")
        let lib = root.appendingPathComponent("vfcommit_lib")
        var parts: [String] = []

        if let values = try? script.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
           let modified = values.contentModificationDate,
           let size = values.fileSize {
            parts.append("vfcommit.py:\(size):\(modified.timeIntervalSince1970)")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: lib,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return parts.joined(separator: "|")
        }

        for case let url as URL in enumerator where url.pathExtension == "py" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate,
                  let size = values.fileSize else { continue }
            let relative = url.lastPathComponent
            parts.append("\(relative):\(size):\(modified.timeIntervalSince1970)")
        }

        return parts.sorted().joined(separator: "|")
    }

    private static func removePythonCaches(under root: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator where url.lastPathComponent == "__pycache__" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func commit(_ request: CommitRequest) async throws -> CommitResult {
        guard let helperURL = helperURL ?? Self.defaultHelperURL() else {
            throw CommitServiceError.helperNotFound
        }
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            throw CommitServiceError.helperUnavailable(helperURL.path)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)

        let process = Process()
        if pythonExecutable.hasSuffix("env") {
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = ["python3", helperURL.path]
        } else {
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = [helperURL.path]
        }

        let toolsDir = helperURL.deletingLastPathComponent()
        process.currentDirectoryURL = toolsDir

        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PYTHONPATH"] ?? ""
        let pythonPath = toolsDir.path
        environment["PYTHONPATH"] = existingPath.isEmpty ? pythonPath : "\(pythonPath):\(existingPath)"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        stdinPipe.fileHandleForWriting.write(requestData)
        try stdinPipe.fileHandleForWriting.close()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            let detail = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(process.terminationStatus)"
            throw CommitServiceError.helperFailed(detail)
        }

        do {
            return try VarFontJSON.decode(CommitResult.self, from: stdoutData)
        } catch {
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdoutText = String(data: stdoutData.prefix(400), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail: String
            if !stdoutText.isEmpty {
                detail = stdoutText
            } else if !stderrText.isEmpty {
                detail = stderrText
            } else {
                detail = error.localizedDescription
            }
            throw CommitServiceError.invalidHelperOutput(detail)
        }
    }
}
