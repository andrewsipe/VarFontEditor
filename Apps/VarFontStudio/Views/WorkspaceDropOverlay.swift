import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceDropZone: Equatable {
    case none
    case addExisting
    case newProject
}

// MARK: - Drop handling (single delegate — avoids competing onDrop targets)

struct WorkspaceDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    @Binding var activeZone: WorkspaceDropZone
    let dropHeight: CGFloat
    let isEmptyWorkspace: Bool
    let isBusy: Bool
    let onDropURLs: ([URL], FontDropDisposition) -> Void

    func dropEntered(info: DropInfo) {
        guard !isBusy else { return }
        isTargeted = true
        updateZone(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !isBusy else {
            return DropProposal(operation: .forbidden)
        }
        updateZone(for: info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        activeZone = .none
    }

    func validateDrop(info: DropInfo) -> Bool {
        !isBusy
    }

    func performDrop(info: DropInfo) -> Bool {
        guard !isBusy else { return false }

        let zone = zone(for: info)
        isTargeted = false
        activeZone = .none
        let disposition = disposition(for: zone)

        let providers = info.itemProviders(for: EditorViewModel.fontDropTypes)
        guard !providers.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadDroppedURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            await MainActor.run {
                onDropURLs(urls, disposition)
            }
        }
        return true
    }

    private func zone(for info: DropInfo) -> WorkspaceDropZone {
        if isEmptyWorkspace {
            return .newProject
        }
        let midpoint = max(dropHeight * 0.5, 1)
        return info.location.y < midpoint ? .addExisting : .newProject
    }

    private func updateZone(for info: DropInfo) {
        activeZone = zone(for: info)
    }

    private func disposition(for zone: WorkspaceDropZone) -> FontDropDisposition {
        switch zone {
        case .newProject, .none:
            return .createNewProject
        case .addExisting:
            return .addToProject
        }
    }

    private func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    continuation.resume(returning: object)
                }
            }
            if let url { return url }
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                          let path = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: URL(fileURLWithPath: path))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Visual overlay

struct WorkspaceDropOverlay: View {
    let isEmptyWorkspace: Bool
    let activeZone: WorkspaceDropZone

    var body: some View {
        if isEmptyWorkspace {
            singleZone
        } else {
            splitZones
        }
    }

    private var singleZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(StudioTypography.emphasis)
                    .foregroundStyle(.tint)
                Text("Drop a variable font to begin")
                    .font(StudioTypography.bodyMedium)
                Text("Creates your first project · TTF, OTF, WOFF, WOFF2")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08))
    }

    private var splitZones: some View {
        VStack(spacing: 0) {
            dropHalf(
                zone: .addExisting,
                title: "Add to project",
                subtitle: "Drop here to add to an existing project",
                tint: StudioColors.dropAddExisting
            )
            .frame(maxHeight: .infinity)

            dropHalf(
                zone: .newProject,
                title: "New project",
                subtitle: "Drop here to start a separate project",
                tint: StudioColors.dropNewProject
            )
            .frame(maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.12))
    }

    private func dropHalf(zone: WorkspaceDropZone, title: String, subtitle: String, tint: Color) -> some View {
        let targeted = activeZone == zone
        return ZStack {
            tint.opacity(targeted ? 0.22 : 0.08)

            VStack(spacing: 6) {
                Text(title)
                    .font(StudioTypography.emphasis)
                Text(subtitle)
                    .font(StudioTypography.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: StudioRadius.row))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.row)
                    .strokeBorder(targeted ? tint : Color.secondary.opacity(0.3), lineWidth: targeted ? 2 : 1)
            }
            .padding(20)
        }
    }
}

struct EmptyWorkspaceView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Drop a variable font to begin")
                .font(StudioTypography.emphasis)
            Text("Or use File → Open Font…")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
