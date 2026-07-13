import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop handling (single delegate — avoids competing onDrop targets)

struct WorkspaceDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let globalOrigin: CGPoint
    let isBusy: Bool
    let activeProjectID: String?
    let isInternalDragActive: () -> Bool
    let coordinator: WorkspaceDragCoordinator
    let onDropURLs: ([URL], WorkspaceDropTarget) -> Void

    func dropEntered(info: DropInfo) {
        guard acceptsFileDrop(info) else { return }
        isTargeted = true
        let global = globalPoint(for: info)
        let count = info.itemProviders(for: EditorViewModel.fontDropTypes).count
        coordinator.beginExternalFileDrop(fileCount: count, at: global)
        coordinator.updateExternalFileDrop(at: global, activeProjectID: activeProjectID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard acceptsFileDrop(info) else {
            return DropProposal(operation: .forbidden)
        }
        let global = globalPoint(for: info)
        coordinator.updateExternalFileDrop(at: global, activeProjectID: activeProjectID)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        coordinator.cancelExternalFileDrop()
    }

    func validateDrop(info: DropInfo) -> Bool {
        acceptsFileDrop(info)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard acceptsFileDrop(info) else { return false }

        let global = globalPoint(for: info)
        coordinator.updateExternalFileDrop(at: global, activeProjectID: activeProjectID)
        let target = coordinator.endExternalFileDrop() ?? .newProject
        isTargeted = false

        let providers = info.itemProviders(for: EditorViewModel.fontDropTypes)
        guard !providers.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadDroppedURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else {
                await MainActor.run {
                    // Kept empty so callers can still surface a status via importDroppedFonts —
                    // but when only temp copies were available, tell the user explicitly.
                    onDropURLs([], target)
                }
                return
            }
            await MainActor.run {
                onDropURLs(urls, target)
            }
        }
        return true
    }

    private func globalPoint(for info: DropInfo) -> CGPoint {
        CGPoint(
            x: info.location.x + globalOrigin.x,
            y: info.location.y + globalOrigin.y
        )
    }

    private func acceptsFileDrop(_ info: DropInfo) -> Bool {
        if isBusy || isInternalDragActive() {
            return false
        }
        return !info.itemProviders(for: EditorViewModel.fontDropTypes).isEmpty
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        // Always prefer the original Finder path. Never use loadFileRepresentation —
        // that yields a temporary copy, and .varf relative font paths would resolve
        // beside /var/folders/... instead of next to the real project file.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadFileURLItem(from: provider) {
            return url
        }

        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    continuation.resume(returning: object)
                }
            }
            if let url, !isTemporaryDropLocation(url) {
                return url.standardizedFileURL
            }
        }

        // Last resort: in-place representation keeps the original path when possible.
        for typeID in provider.registeredTypeIdentifiers {
            if let url = await loadInPlaceURL(from: provider, typeIdentifier: typeID),
               !isTemporaryDropLocation(url) {
                return url
            }
        }

        return nil
    }

    private func loadFileURLItem(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let resolved: URL?
                if let url = item as? URL {
                    resolved = url
                } else if let data = item as? Data {
                    // Finder usually provides a file:// URL as UTF-8 data — not a raw path.
                    if let url = URL(dataRepresentation: data, relativeTo: nil) {
                        resolved = url
                    } else if let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) {
                        resolved = URL(string: text) ?? URL(fileURLWithPath: text)
                    } else {
                        resolved = nil
                    }
                } else if let text = item as? String {
                    resolved = URL(string: text) ?? URL(fileURLWithPath: text)
                } else {
                    resolved = nil
                }
                continuation.resume(returning: resolved?.standardizedFileURL)
            }
        }
    }

    private func loadInPlaceURL(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, _ in
                guard let url, isInPlace else {
                    // Coordinated/temp copies are unusable for .varf (relative font paths).
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url.standardizedFileURL)
            }
        }
    }

    private func isTemporaryDropLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        // Coordinated/temporary copies break .varf relative font resolution.
        return path.contains("/VarFontDrop/")
            || path.contains("/TemporaryItems/")
    }
}

// MARK: - Empty workspace hint (no full-sheet overlay)

struct EmptyWorkspaceView: View {
    var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "plus.circle.fill" : "arrow.down.doc")
                .font(.system(size: 36))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                .animation(.easeOut(duration: 0.12), value: isDropTargeted)

            Text(isDropTargeted ? "Drop to open" : "Drop fonts or projects to begin")
                .font(StudioTypography.emphasis)
                .foregroundStyle(isDropTargeted ? Color.accentColor : .primary)

            Text(isDropTargeted
                ? "Projects open as tabs · fonts start a new project"
                : "Or use File → Open… · TTF, OTF, WOFF, WOFF2, VARF · folders OK")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceDropZoneHighlight(
            isActive: isDropTargeted,
            tint: StudioColors.dropNewProject
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Drop zone highlight (5% fill + 1px bottom edge)

struct WorkspaceDropZoneHighlight: ViewModifier {
    let isActive: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background {
                if isActive {
                    tint.opacity(StudioColors.dropZoneFillOpacity)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? tint : .clear)
                    .frame(height: 1)
            }
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

extension View {
    func workspaceDropZoneHighlight(isActive: Bool, tint: Color) -> some View {
        modifier(WorkspaceDropZoneHighlight(isActive: isActive, tint: tint))
    }
}
