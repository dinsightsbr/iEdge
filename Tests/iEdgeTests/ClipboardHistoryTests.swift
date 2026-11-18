import XCTest
@testable import iEdge

final class ClipboardHistoryTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func text(_ value: String, minutesAgo: Double = 0, pinned: Bool = false) -> ClipboardEntry {
        ClipboardEntry(content: .text(value), date: base.addingTimeInterval(-minutesAgo * 60), pinned: pinned)
    }

    private func texts(_ history: ClipboardHistory) -> [String] {
        history.entries.map(\.summary)
    }

    // MARK: Insert and dedup

    func testInsertPutsNewestOnTop() {
        var history = ClipboardHistory(maxEntries: 50)
        history.insert(text("a", minutesAgo: 2))
        history.insert(text("b", minutesAgo: 1))
        XCTAssertEqual(texts(history), ["b", "a"])
    }

    func testSameContentMovesToTopWithoutDuplicating() {
        var history = ClipboardHistory(maxEntries: 50)
        let first = text("a", minutesAgo: 3)
        history.insert(first)
        history.insert(text("b", minutesAgo: 2))
        var again = text("a", minutesAgo: 1)
        again.sourceBundleID = "com.apple.Notes"
        let dropped = history.insert(again)

        XCTAssertEqual(texts(history), ["a", "b"])
        XCTAssertEqual(history.entries[0].id, first.id, "keeps the existing entry")
        XCTAssertEqual(history.entries[0].date, again.date, "with the new date")
        XCTAssertEqual(history.entries[0].sourceBundleID, "com.apple.Notes")
        XCTAssertTrue(dropped.isEmpty, "identical content leaves no file behind")
    }

    func testDuplicateKeepsPin() {
        var history = ClipboardHistory(maxEntries: 50)
        history.insert(text("a", minutesAgo: 3, pinned: true))
        history.insert(text("a"))
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertTrue(history.entries[0].pinned)
    }

    func testCustomEquivalenceReturnsIncomingAsDropped() {
        var history = ClipboardHistory(maxEntries: 50)
        let old = ClipboardEntry(content: .image(path: "/a.png", thumbnailPath: nil, width: 10, height: 10, byteCount: 5), date: base)
        let new = ClipboardEntry(content: .image(path: "/b.png", thumbnailPath: nil, width: 10, height: 10, byteCount: 5), date: base.addingTimeInterval(1))
        history.insert(old)
        let dropped = history.insert(new) { _, _ in true }
        XCTAssertEqual(history.entries.map(\.id), [old.id])
        XCTAssertEqual(dropped.map(\.id), [new.id], "the new file must be deleted by the owner")
    }

    // MARK: Limit

    func testLimitDropsOldestUnpinned() {
        var history = ClipboardHistory(maxEntries: 3)
        for (index, value) in ["a", "b", "c"].enumerated() {
            history.insert(text(value, minutesAgo: Double(10 - index)))
        }
        let dropped = history.insert(text("d"))
        XCTAssertEqual(texts(history), ["d", "c", "b"])
        XCTAssertEqual(dropped.map(\.summary), ["a"])
    }

    func testLimitNeverDropsPinned() {
        var history = ClipboardHistory(maxEntries: 2)
        history.insert(text("old pinned", minutesAgo: 10, pinned: true))
        history.insert(text("b", minutesAgo: 5))
        let dropped = history.insert(text("c"))
        XCTAssertEqual(Set(texts(history)), ["old pinned", "c"])
        XCTAssertEqual(dropped.map(\.summary), ["b"])
    }

    func testMorePinsThanLimitKeepsAllPins() {
        var history = ClipboardHistory(maxEntries: 2)
        history.insert(text("p1", minutesAgo: 3, pinned: true))
        history.insert(text("p2", minutesAgo: 2, pinned: true))
        history.insert(text("p3", minutesAgo: 1, pinned: true))
        let dropped = history.insert(text("x"))
        XCTAssertEqual(Set(texts(history)), ["p1", "p2", "p3"])
        XCTAssertEqual(dropped.map(\.summary), ["x"])
    }

    func testLoweringLimitTrims() {
        var history = ClipboardHistory(maxEntries: 10)
        for index in 0..<5 { history.insert(text("\(index)", minutesAgo: Double(10 - index))) }
        let dropped = history.setMaxEntries(2)
        XCTAssertEqual(texts(history), ["4", "3"])
        XCTAssertEqual(dropped.count, 3)
    }

    func testUnpinningOverLimitTrims() {
        // A pinned entry over the limit (the limit was lowered while it was pinned).
        let pinned = text("p", minutesAgo: 5, pinned: true)
        var history = ClipboardHistory(entries: [pinned, text("new")], maxEntries: 1)
        XCTAssertEqual(history.entries.count, 2)
        let dropped = history.togglePin(id: pinned.id)
        XCTAssertEqual(texts(history), ["new"])
        XCTAssertEqual(dropped.map(\.id), [pinned.id])
    }

    // MARK: Order

    func testSortedPutsPinnedFirstThenMostRecent() {
        let history = ClipboardHistory(entries: [
            text("old", minutesAgo: 30),
            text("pinned old", minutesAgo: 60, pinned: true),
            text("new", minutesAgo: 1),
            text("pinned new", minutesAgo: 10, pinned: true),
        ], maxEntries: 50)
        XCTAssertEqual(history.sorted.map(\.summary), ["pinned new", "pinned old", "new", "old"])
    }

    func testTouchMovesToTop() {
        var history = ClipboardHistory(maxEntries: 50)
        let a = text("a", minutesAgo: 5)
        history.insert(a)
        history.insert(text("b", minutesAgo: 1))
        history.touch(id: a.id, date: base)
        XCTAssertEqual(texts(history), ["a", "b"])
    }

    // MARK: Remove and clear

    func testRemove() {
        var history = ClipboardHistory(maxEntries: 50)
        let a = text("a", minutesAgo: 2)
        history.insert(a)
        history.insert(text("b"))
        XCTAssertEqual(history.remove(id: a.id)?.id, a.id)
        XCTAssertEqual(texts(history), ["b"])
        XCTAssertNil(history.remove(id: UUID()))
    }

    func testClearKeepsPinned() {
        var history = ClipboardHistory(maxEntries: 50)
        history.insert(text("a", minutesAgo: 3))
        history.insert(text("p", minutesAgo: 2, pinned: true))
        history.insert(text("b", minutesAgo: 1))
        let removed = history.clear()
        XCTAssertEqual(texts(history), ["p"])
        XCTAssertEqual(Set(removed.map(\.summary)), ["a", "b"])
    }

    // MARK: Monitor rules

    func testConcealedTransientAndAutoGeneratedTypesAreIgnored() {
        XCTAssertTrue(ClipboardMonitor.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardMonitor.shouldIgnore(types: ["org.nspasteboard.TransientType"]))
        XCTAssertTrue(ClipboardMonitor.shouldIgnore(types: ["public.png", "org.nspasteboard.AutoGeneratedType"]))
        XCTAssertFalse(ClipboardMonitor.shouldIgnore(types: ["public.utf8-plain-text", "public.html"]))
        XCTAssertFalse(ClipboardMonitor.shouldIgnore(types: []))
    }

    func testExcludedApps() {
        let excluded = ClipboardSettings.defaultExcludedBundleIDs
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.1password.1password", excluded: excluded))
        XCTAssertTrue(ClipboardMonitor.isExcluded(bundleID: "com.apple.KeychainAccess", excluded: excluded), "bundle ids compare case-insensitively")
        XCTAssertFalse(ClipboardMonitor.isExcluded(bundleID: "com.apple.Safari", excluded: excluded))
        XCTAssertFalse(ClipboardMonitor.isExcluded(bundleID: nil, excluded: excluded))
    }

    func testLinkDetection() {
        XCTAssertEqual(ClipboardMonitor.linkString(from: " https://apple.com/mac \n"), "https://apple.com/mac")
        XCTAssertEqual(ClipboardMonitor.linkString(from: "mailto:a@b.com"), "mailto:a@b.com")
        XCTAssertNil(ClipboardMonitor.linkString(from: "veja https://apple.com"))
        XCTAssertNil(ClipboardMonitor.linkString(from: "file:///etc/hosts"))
        XCTAssertNil(ClipboardMonitor.linkString(from: "https://"))
        XCTAssertNil(ClipboardMonitor.linkString(from: "texto qualquer"))
    }

    func testRelativeTime() {
        let now = base
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-20), now: now), "agora")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-120), now: now), "há 2 min")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-3 * 3600), now: now), "há 3 h")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-26 * 3600), now: now), "ontem")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-3 * 86_400), now: now), "há 3 d")
    }
}

/// The real store against a temporary folder: persistence and image files.
@MainActor
final class ClipboardStorePersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("iEdgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storage: ClipboardStore.Storage {
        ClipboardStore.Storage(file: directory.appendingPathComponent("clipboard.json"), imagesDirectory: directory.appendingPathComponent("clipboard"))
    }

    private func writeImage(_ name: String) throws -> String {
        try AppPaths.ensureDirectory(storage.imagesDirectory)
        let url = storage.imagesDirectory.appendingPathComponent(name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url.path
    }

    private func savedFile(entries: [ClipboardEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        struct File: Encodable { var version = 1; var entries: [ClipboardEntry] }
        try encoder.encode(File(entries: entries)).write(to: storage.file)
    }

    func testLoadsEntriesAndDeletesOrphanImages() throws {
        let kept = try writeImage("kept.png")
        let orphan = try writeImage("orphan.png")
        let image = ClipboardEntry(content: .image(path: kept, thumbnailPath: nil, width: 1, height: 1, byteCount: 4), date: Date())
        try savedFile(entries: [ClipboardEntry(content: .text("oi"), date: Date().addingTimeInterval(-60)), image])

        let store = ClipboardStore(settings: SettingsStore(demo: true), storage: storage)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan))
    }

    func testClearDeletesImageFilesAndSaves() throws {
        let path = try writeImage("a.png")
        let image = ClipboardEntry(content: .image(path: path, thumbnailPath: nil, width: 1, height: 1, byteCount: 4), date: Date())
        let pinned = ClipboardEntry(content: .text("fixo"), date: Date().addingTimeInterval(-60), pinned: true)
        try savedFile(entries: [image, pinned])

        let store = ClipboardStore(settings: SettingsStore(demo: true), storage: storage)
        store.clear()
        store.flushSave()
        XCTAssertEqual(store.entries.map(\.id), [pinned.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))

        let reloaded = ClipboardStore(settings: SettingsStore(demo: true), storage: storage)
        XCTAssertEqual(reloaded.entries.map(\.id), [pinned.id])
    }

    func testPersistOffDeletesFile() throws {
        try savedFile(entries: [ClipboardEntry(content: .text("oi"))])
        let settings = SettingsStore(demo: true)
        settings.settings.clipboard.persist = false
        let store = ClipboardStore(settings: settings, storage: storage)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.file.path))
    }

    func testLoweringMaxEntriesTrims() throws {
        let entries = (0..<30).map { ClipboardEntry(content: .text("\($0)"), date: Date().addingTimeInterval(Double(-$0))) }
        try savedFile(entries: entries)
        let settings = SettingsStore(demo: true)
        let store = ClipboardStore(settings: settings, storage: storage)
        XCTAssertEqual(store.entries.count, 30)
        settings.settings.clipboard.maxEntries = 20
        store.flushTrim()
        XCTAssertEqual(store.entries.count, 20)
        XCTAssertEqual(store.entries.first?.summary, "0")
    }

    /// Dragging the "Tamanho" slider down and back up must not evict anything.
    func testMaxEntriesDraggedThroughLowValuesKeepsEntries() throws {
        let entries = (0..<30).map { ClipboardEntry(content: .text("\($0)"), date: Date().addingTimeInterval(Double(-$0))) }
        try savedFile(entries: entries)
        let settings = SettingsStore(demo: true)
        let store = ClipboardStore(settings: settings, storage: storage)
        for value in [40, 30, 20, 30, 50] { settings.settings.clipboard.maxEntries = value }
        store.flushTrim()
        XCTAssertEqual(store.entries.count, 30)

        let settled = expectation(description: "trim after the value settles")
        settings.settings.clipboard.maxEntries = 20
        XCTAssertEqual(store.entries.count, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + ClipboardStore.trimDelay + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: ClipboardStore.trimDelay + 2)
        XCTAssertEqual(store.entries.count, 20)
    }

    func testUnreadableFileIsBackedUpAndImagesKept() throws {
        let image = try writeImage("kept.png")
        try Data("{ not json".utf8).write(to: storage.file)

        let store = ClipboardStore(settings: SettingsStore(demo: true), storage: storage)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: image))
        let backup = storage.file.appendingPathExtension("corrompido")
        XCTAssertEqual(try Data(contentsOf: backup), Data("{ not json".utf8))
    }

    /// An image path in clipboard.json outside clipboard/ is never deleted.
    func testEvictionNeverDeletesFilesOutsideImagesFolder() throws {
        let outside = directory.appendingPathComponent("importante.txt")
        try Data("x".utf8).write(to: outside)
        let entry = ClipboardEntry(content: .image(path: outside.path, thumbnailPath: nil, width: 1, height: 1, byteCount: 1), date: Date())
        try savedFile(entries: [entry])

        let store = ClipboardStore(settings: SettingsStore(demo: true), storage: storage)
        XCTAssertEqual(store.entries.count, 1)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testImageFilesStorePNGThumbnailAndDedup() throws {
        let image = NSImage(size: NSSize(width: 400, height: 200), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let first = try ClipboardImageFiles.store(tiff, id: UUID(), in: storage.imagesDirectory)
        let second = try ClipboardImageFiles.store(tiff, id: UUID(), in: storage.imagesDirectory)

        XCTAssertTrue(first.path.hasSuffix(".png"))
        XCTAssertGreaterThan(first.width, 0)
        let thumbPath = try XCTUnwrap(first.thumbnailPath)
        let thumb = try XCTUnwrap(NSImage(contentsOfFile: thumbPath)?.representations.first)
        XCTAssertLessThanOrEqual(max(thumb.pixelsWide, thumb.pixelsHigh), ClipboardImageFiles.thumbnailPixels)

        let a = ClipboardContent.image(path: first.path, thumbnailPath: first.thumbnailPath, width: first.width, height: first.height, byteCount: first.byteCount)
        let b = ClipboardContent.image(path: second.path, thumbnailPath: second.thumbnailPath, width: second.width, height: second.height, byteCount: second.byteCount)
        XCTAssertTrue(ClipboardImageFiles.sameImage(a, b))

        ClipboardImageFiles.delete(a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbPath))
    }

    func testWriteTextAndFilesToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("iEdgeTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let store = ClipboardStore(settings: SettingsStore(demo: true), previewEntries: [])

        XCTAssertTrue(store.write(ClipboardEntry(content: .text("olá")), to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "olá")

        XCTAssertTrue(store.write(ClipboardEntry(content: .url("https://apple.com")), to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .URL), "https://apple.com")
        XCTAssertEqual(pasteboard.string(forType: .string), "https://apple.com")

        XCTAssertTrue(store.write(ClipboardEntry(content: .files(["/tmp/a.txt", "/tmp/b.txt"])), to: pasteboard))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.map(\.path), ["/tmp/a.txt", "/tmp/b.txt"])
    }
}
