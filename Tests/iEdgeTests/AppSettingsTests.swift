import XCTest
@testable import iEdge

final class AppSettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testRoundTripKeepsEveryField() throws {
        var settings = AppSettings()
        settings.edges = [.right]
        settings.forceEdgeWithDock = true
        settings.dwellMs = 220
        settings.pushDistance = 20
        settings.cornerExclusion = 48
        settings.magnification = 1.8
        settings.tileSize = 50
        settings.showLabels = false
        settings.haptics = false
        settings.items.append(SidebarItem(kind: .openApp(path: "/Applications/Safari.app"), title: "Safari"))
        settings.items.append(SidebarItem(kind: .openURL("https://example.com"), title: "Site"))
        settings.items.append(SidebarItem(kind: .shortcut(name: "Modo foco"), title: "Foco"))
        settings.items.append(SidebarItem(kind: .shell(command: "open ~"), title: "Home", enabled: false))
        settings.items[1].enabled = false
        settings.screenshot = ScreenshotSettings(destination: .file, folderPath: "/tmp/caps", playSound: false, showToast: false)
        settings.clipboard = ClipboardSettings(persist: false, maxEntries: 120, autoPaste: true, excludedBundleIDs: ["a.b"])
        settings.launchAtLogin = true
        settings.paused = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testDefaults() {
        let settings = AppSettings()
        XCTAssertEqual(settings.edges, [.left, .right])
        XCTAssertEqual(settings.dwellMs, 150)
        XCTAssertEqual(settings.pushDistance, 14)
        XCTAssertEqual(settings.magnification, 1.6)
        XCTAssertEqual(settings.tileSize, 44)
        XCTAssertEqual(settings.items.map(\.kind), [.screenshotFull, .screenshotArea, .screenshotWindow, .clipboard, .captureTool])
        XCTAssertEqual(settings.items.map(\.symbol), ["display", "rectangle.dashed", "macwindow", "doc.on.clipboard", "record.circle"])
        XCTAssertTrue(settings.items.allSatisfy { $0.isBuiltIn && $0.enabled })
        XCTAssertEqual(settings.screenshot.destination, .both)
        XCTAssertEqual(settings.clipboard.maxEntries, 50)
        XCTAssertFalse(settings.clipboard.autoPaste)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        XCTAssertEqual(try decode("{}"), AppSettings())
    }

    func testOldJSONWithoutNewKeysKeepsWhatItHas() throws {
        let settings = try decode("""
        {
          "edges": ["left"],
          "dwellMs": 300,
          "screenshot": { "destination": "clipboard" },
          "clipboard": { "maxEntries": 80 }
        }
        """)
        XCTAssertEqual(settings.edges, [.left])
        XCTAssertEqual(settings.dwellMs, 300)
        XCTAssertEqual(settings.screenshot.destination, .clipboard)
        XCTAssertTrue(settings.screenshot.playSound)
        XCTAssertEqual(settings.clipboard.maxEntries, 80)
        XCTAssertTrue(settings.clipboard.persist)
        XCTAssertEqual(settings.clipboard.excludedBundleIDs, ClipboardSettings.defaultExcludedBundleIDs)
        XCTAssertEqual(settings.magnification, 1.6)
        XCTAssertEqual(settings.items, SidebarItem.defaults)
        XCTAssertFalse(settings.paused)
    }

    func testWrongTypesAndOutOfRangeValuesFallBackOrClamp() throws {
        let settings = try decode("""
        { "dwellMs": "rápido", "magnification": 9, "tileSize": 10, "haptics": "sim",
          "edges": ["left", "top"], "clipboard": { "maxEntries": 5000 } }
        """)
        XCTAssertEqual(settings.dwellMs, 150)
        XCTAssertEqual(settings.magnification, 2.0)
        XCTAssertEqual(settings.tileSize, 36)
        XCTAssertTrue(settings.haptics)
        XCTAssertEqual(settings.edges, [.left])
        XCTAssertEqual(settings.clipboard.maxEntries, 200)
    }

    func testItemsSkipUnknownKindsAndRestoreMissingBuiltIns() throws {
        let settings = try decode("""
        { "items": [
            { "id": "1E0D6E00-0000-4000-8000-000000000004", "kind": { "type": "clipboard" },
              "title": "Clipboard", "symbol": "doc.on.clipboard", "enabled": false, "isBuiltIn": true },
            { "kind": { "type": "teleport", "where": "Marte" }, "title": "Futuro" },
            { "kind": { "type": "openURL", "url": "https://example.com" }, "title": "Site" },
            { "kind": { "type": "clipboard" }, "title": "Duplicado" }
        ] }
        """)
        XCTAssertEqual(settings.items.count, 6)
        XCTAssertEqual(settings.items[0].kind, .clipboard)
        XCTAssertFalse(settings.items[0].enabled)
        XCTAssertEqual(settings.items[1].kind, .openURL("https://example.com"))
        XCTAssertEqual(settings.items[1].symbol, "link")
        XCTAssertFalse(settings.items[1].isBuiltIn)
        XCTAssertEqual(settings.items.dropFirst(2).map(\.kind), [.screenshotFull, .screenshotArea, .screenshotWindow, .captureTool])
    }

    func testActionKindEncodingIsFlat() throws {
        let data = try JSONEncoder().encode(ActionKind.shell(command: "ls"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["type": "shell", "command": "ls"])
    }

    func testClipboardEntryRoundTrip() throws {
        let entries = [
            ClipboardEntry(content: .text("olá"), date: Date(timeIntervalSince1970: 1_000), sourceBundleID: "com.apple.Notes", sourceAppName: "Notas", pinned: true),
            ClipboardEntry(content: .image(path: "/x.png", thumbnailPath: nil, width: 10, height: 20, byteCount: 300), date: Date(timeIntervalSince1970: 2_000)),
            ClipboardEntry(content: .files(["/a", "/b"]), date: Date(timeIntervalSince1970: 3_000)),
            ClipboardEntry(content: .url("https://example.com"), date: Date(timeIntervalSince1970: 4_000)),
        ]
        let data = try JSONEncoder().encode(entries)
        XCTAssertEqual(try JSONDecoder().decode([ClipboardEntry].self, from: data), entries)
    }

    @MainActor
    func testSettingsStoreSavesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iedge-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SettingsStore(fileURL: url)
        store.settings.dwellMs = 333
        store.flush()
        XCTAssertEqual(SettingsStore(fileURL: url).settings.dwellMs, 333)
    }

    @MainActor
    func testDemoStoreWritesNothing() {
        let store = SettingsStore(demo: true)
        XCTAssertNil(store.fileURL)
        store.settings.paused = true
        store.flush()
        XCTAssertTrue(store.settings.paused)
    }
}
