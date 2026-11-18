import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG files of image entries: `clipboard/<uuid>.png` plus a small `<uuid>-thumb.png` for the list.
/// Uses ImageIO only, so it runs off the main thread.
enum ClipboardImageFiles {
    /// Longest side of the list thumbnail in pixels (40 pt at up to 3×).
    static let thumbnailPixels = 120

    struct Stored {
        var path: String
        var thumbnailPath: String?
        var width: Double
        var height: Double
        var byteCount: Int
    }

    /// Converts pasteboard image data (PNG or TIFF) to PNG and writes it with its thumbnail.
    static func store(_ data: Data, id: UUID, in directory: URL) throws -> Stored {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        let png = isPNG ? data : try pngData(image)

        try AppPaths.ensureDirectory(directory)
        let url = directory.appendingPathComponent("\(id.uuidString).png")
        try png.write(to: url, options: .atomic)

        var thumbnailPath: String?
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if max(image.width, image.height) > thumbnailPixels,
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
           let thumbData = try? pngData(thumbnail) {
            let thumbURL = directory.appendingPathComponent("\(id.uuidString)-thumb.png")
            if (try? thumbData.write(to: thumbURL, options: .atomic)) != nil {
                thumbnailPath = thumbURL.path
            }
        }
        return Stored(path: url.path, thumbnailPath: thumbnailPath, width: Double(image.width), height: Double(image.height), byteCount: png.count)
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    /// Files an entry owns (nothing for non-image entries).
    static func paths(of content: ClipboardContent) -> [String] {
        guard case let .image(path, thumbnailPath, _, _, _) = content else { return [] }
        return [path, thumbnailPath].compactMap { $0 }.filter { !$0.isEmpty }
    }

    static func delete(_ content: ClipboardContent) {
        for path in paths(of: content) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Two image entries hold the same picture: same size and byte-identical PNG.
    static func sameImage(_ a: ClipboardContent, _ b: ClipboardContent) -> Bool {
        guard case let .image(pathA, _, wA, hA, bytesA) = a, case let .image(pathB, _, wB, hB, bytesB) = b else { return false }
        if pathA == pathB { return true }
        guard wA == wB, hA == hB, bytesA == bytesB,
              let dataA = FileManager.default.contents(atPath: pathA),
              let dataB = FileManager.default.contents(atPath: pathB) else { return false }
        return dataA == dataB
    }
}
