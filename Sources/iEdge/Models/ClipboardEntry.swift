import Foundation

/// What was copied. Images live as PNG files under Application Support/iEdge/clipboard/.
enum ClipboardContent: Codable, Hashable {
    case text(String)
    /// `path` is the PNG; `thumbnailPath` an optional smaller copy for the list.
    case image(path: String, thumbnailPath: String?, width: Double, height: Double, byteCount: Int)
    /// File URLs as absolute paths.
    case files([String])
    case url(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, path, thumbnailPath, width, height, byteCount, paths, url
    }

    private enum ContentType: String, Codable { case text, image, files, url }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(ContentType.self, forKey: .type) {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))
        case .image:
            self = .image(
                path: try c.decode(String.self, forKey: .path),
                thumbnailPath: c.value(.thumbnailPath),
                width: c.value(.width) ?? 0,
                height: c.value(.height) ?? 0,
                byteCount: c.value(.byteCount) ?? 0
            )
        case .files:
            self = .files(try c.decode([String].self, forKey: .paths))
        case .url:
            self = .url(try c.decode(String.self, forKey: .url))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode(ContentType.text, forKey: .type)
            try c.encode(text, forKey: .text)
        case let .image(path, thumbnailPath, width, height, byteCount):
            try c.encode(ContentType.image, forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
            try c.encode(byteCount, forKey: .byteCount)
        case .files(let paths):
            try c.encode(ContentType.files, forKey: .type)
            try c.encode(paths, forKey: .paths)
        case .url(let url):
            try c.encode(ContentType.url, forKey: .type)
            try c.encode(url, forKey: .url)
        }
    }
}

struct ClipboardEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var content: ClipboardContent
    var date: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    var pinned: Bool

    init(id: UUID = UUID(), content: ClipboardContent, date: Date = Date(), sourceBundleID: String? = nil, sourceAppName: String? = nil, pinned: Bool = false) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, date, sourceBundleID, sourceAppName, pinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.value(.id) ?? UUID(),
            content: try c.decode(ClipboardContent.self, forKey: .content),
            date: c.value(.date) ?? Date(),
            sourceBundleID: c.value(.sourceBundleID),
            sourceAppName: c.value(.sourceAppName),
            pinned: c.value(.pinned) ?? false
        )
    }

    /// One-line description for labels and accessibility.
    var summary: String {
        switch content {
        case .text(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .image(_, _, width, height, _):
            return width > 0 ? "Imagem \(Int(width)) × \(Int(height))" : "Imagem"
        case .files(let paths):
            let names = paths.map { ($0 as NSString).lastPathComponent }
            return names.count == 1 ? names[0] : "\(names.count) arquivos"
        case .url(let url):
            return url
        }
    }
}
