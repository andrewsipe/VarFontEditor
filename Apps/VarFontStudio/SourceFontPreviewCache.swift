import AppKit
import CoreText
import Foundation

/// Cached source-font descriptor for live glyph preview.
///
/// Loads once per font file (via the same temp-cache path as vfcommit), then
/// applies variation coordinates without re-reading the font.
@MainActor
final class SourceFontPreviewCache {
    private struct Entry {
        let fontID: String
        let sourcePath: String
        let cachePath: String
        let descriptor: CTFontDescriptor
    }

    private var entry: Entry?

    func invalidate(fontID: String? = nil) {
        if let fontID {
            if entry?.fontID == fontID {
                entry = nil
            }
        } else {
            entry = nil
        }
    }

    /// Returns an `NSFont` at `size` with native fvar coordinates applied.
    /// Coordinates for axes absent from the source font are ignored.
    func nsFont(
        fontID: String,
        bookmark: Data?,
        sourcePath: String,
        coords: [String: Double],
        size: CGFloat
    ) -> NSFont? {
        guard let descriptor = baseDescriptor(
            fontID: fontID,
            bookmark: bookmark,
            sourcePath: sourcePath
        ) else {
            return nil
        }

        let variation = variationDictionary(from: coords)
        let attributed: CTFontDescriptor
        if variation.count == 0 {
            attributed = descriptor
        } else {
            attributed = CTFontDescriptorCreateCopyWithAttributes(
                descriptor,
                [kCTFontVariationAttribute: variation] as CFDictionary
            )
        }

        return NSFont(descriptor: attributed as NSFontDescriptor, size: size)
    }

    private func baseDescriptor(
        fontID: String,
        bookmark: Data?,
        sourcePath: String
    ) -> CTFontDescriptor? {
        if let entry,
           entry.fontID == fontID,
           entry.sourcePath == sourcePath,
           FileManager.default.fileExists(atPath: entry.cachePath) {
            return entry.descriptor
        }

        do {
            let cachePath = try SourceFontAccess.helperSourcePath(
                bookmark: bookmark,
                fallbackPath: sourcePath,
                fontID: fontID
            )
            let url = URL(fileURLWithPath: cachePath)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first else {
                entry = nil
                return nil
            }
            entry = Entry(
                fontID: fontID,
                sourcePath: sourcePath,
                cachePath: cachePath,
                descriptor: descriptor
            )
            return descriptor
        } catch {
            entry = nil
            return nil
        }
    }

    private func variationDictionary(from coords: [String: Double]) -> NSDictionary {
        let result = NSMutableDictionary()
        for (tag, value) in coords {
            guard let axisID = fourCharCode(tag) else { continue }
            result[NSNumber(value: axisID)] = NSNumber(value: value)
        }
        return result
    }

    private func fourCharCode(_ tag: String) -> FourCharCode? {
        let bytes = Array(tag.utf8)
        guard bytes.count == 4 else { return nil }
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }
}
