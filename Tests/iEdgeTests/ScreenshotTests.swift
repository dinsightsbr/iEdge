import XCTest
@testable import iEdge

final class ScreenshotTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = utc
        return formatter.date(from: string)!
    }

    // MARK: File name

    func testFileNameUsesPortugueseFormat() {
        XCTAssertEqual(ScreenshotCommand.fileName(for: date("2026-11-18T14:05:33Z"), timeZone: utc),
                       "Captura de Tela 2026-11-18 às 14.05.33.png")
    }

    func testFileNamePadsWithZeros() {
        XCTAssertEqual(ScreenshotCommand.fileName(for: date("2027-01-02T03:04:05Z"), timeZone: utc),
                       "Captura de Tela 2027-01-02 às 03.04.05.png")
    }

    func testFileNameUses24Hours() {
        XCTAssertEqual(ScreenshotCommand.fileName(for: date("2026-11-18T23:59:59Z"), timeZone: utc),
                       "Captura de Tela 2026-11-18 às 23.59.59.png")
    }

    func testFileNameFollowsTimeZone() {
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        XCTAssertEqual(ScreenshotCommand.fileName(for: date("2026-11-18T14:05:33Z"), timeZone: saoPaulo),
                       "Captura de Tela 2026-11-18 às 11.05.33.png")
    }

    func testUniqueFileURLAddsCounter() {
        let folder = URL(fileURLWithPath: "/tmp/caps", isDirectory: true)
        let name = "Captura de Tela 2026-11-18 às 14.05.33.png"
        var taken: Set<String> = []
        XCTAssertEqual(ScreenshotCommand.uniqueFileURL(in: folder, name: name) { taken.contains($0.lastPathComponent) }.lastPathComponent, name)
        taken = [name, "Captura de Tela 2026-11-18 às 14.05.33 (2).png"]
        XCTAssertEqual(ScreenshotCommand.uniqueFileURL(in: folder, name: name) { taken.contains($0.lastPathComponent) }.lastPathComponent,
                       "Captura de Tela 2026-11-18 às 14.05.33 (3).png")
    }

    // MARK: Arguments

    func testFullScreenOnDisplayToFile() {
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .full(display: 2), output: .file("/tmp/a.png"), playSound: true),
                       ["-D", "2", "/tmp/a.png"])
    }

    func testAreaToFile() {
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .area, output: .file("/tmp/a.png"), playSound: true),
                       ["-i", "-s", "/tmp/a.png"])
    }

    func testWindowToFile() {
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .window, output: .file("/tmp/a.png"), playSound: true),
                       ["-i", "-w", "/tmp/a.png"])
    }

    func testClipboardDestinationUsesDashC() {
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .area, output: .clipboard, playSound: true),
                       ["-i", "-s", "-c"])
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .full(display: 1), output: .clipboard, playSound: true),
                       ["-D", "1", "-c"])
    }

    func testSoundOffAddsDashX() {
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .window, output: .file("/tmp/a.png"), playSound: false),
                       ["-x", "-i", "-w", "/tmp/a.png"])
    }

    func testPathWithSpacesStaysOneArgument() {
        let path = "/Users/a/Desktop/Captura de Tela 2026-11-18 às 14.05.33.png"
        XCTAssertEqual(ScreenshotCommand.arguments(mode: .area, output: .file(path), playSound: true).last, path)
    }

    func testDisplayNumberIsPositionPlusOne() {
        let displays: [CGDirectDisplayID] = [69_733_248, 4, 731]
        XCTAssertEqual(ScreenshotCommand.displayNumber(of: 69_733_248, in: displays), 1)
        XCTAssertEqual(ScreenshotCommand.displayNumber(of: 731, in: displays), 3)
        XCTAssertNil(ScreenshotCommand.displayNumber(of: 9, in: displays))
    }

    // MARK: Folder

    func testFolderPrefersCustomThenSystemThenDesktop() {
        let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
        let existing: Set<String> = ["/Users/a/Pictures/Caps", "/Volumes/X/Shots"]
        let isDirectory: (URL) -> Bool = { existing.contains($0.path) }

        XCTAssertEqual(ScreenshotCommand.folder(custom: "/Volumes/X/Shots", systemLocation: "/Users/a/Pictures/Caps", home: home, isDirectory: isDirectory).path,
                       "/Volumes/X/Shots")
        XCTAssertEqual(ScreenshotCommand.folder(custom: "/missing", systemLocation: "/Users/a/Pictures/Caps", home: home, isDirectory: isDirectory).path,
                       "/Users/a/Pictures/Caps")
        XCTAssertEqual(ScreenshotCommand.folder(custom: nil, systemLocation: nil, home: home, isDirectory: isDirectory).path,
                       "/Users/a/Desktop")
    }

    // MARK: Custom actions

    func testShortcutAndShellUseArgumentArrays() {
        let shortcut = CustomActions.processCommand(for: .shortcut(name: "Meu atalho"))
        XCTAssertEqual(shortcut?.executable.path, "/usr/bin/shortcuts")
        XCTAssertEqual(shortcut?.arguments, ["run", "Meu atalho"])

        let command = "echo \"oi\"; ls ~ | wc -l"
        let shell = CustomActions.processCommand(for: .shell(command: command))
        XCTAssertEqual(shell?.executable.path, "/bin/zsh")
        XCTAssertEqual(shell?.arguments, ["-lc", command])

        XCTAssertNil(CustomActions.processCommand(for: .shell(command: "  ")))
        XCTAssertNil(CustomActions.processCommand(for: .shortcut(name: "")))
        XCTAssertNil(CustomActions.processCommand(for: .screenshotArea))
    }

    func testLinkTargets() {
        XCTAssertEqual(CustomActions.target(forLink: "https://apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(CustomActions.target(forLink: "apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(CustomActions.target(forLink: "/Applications")?.isFileURL, true)
        XCTAssertEqual(CustomActions.target(forLink: "~/Documents")?.path, NSHomeDirectory() + "/Documents")
        XCTAssertEqual(CustomActions.target(forLink: "raycast://extensions")?.scheme, "raycast")
        XCTAssertNil(CustomActions.target(forLink: "  "))
        XCTAssertNil(CustomActions.target(forLink: "texto solto"))
    }

    func testProcessTimeoutAndFailureDetail() async {
        let result = await ActionProcess.run(URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", "echo falhou >&2; exit 3"])
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.failureDetail, "falhou")

        let slow = await ActionProcess.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.2)
        XCTAssertTrue(slow.timedOut)
        XCTAssertFalse(slow.succeeded)

        let missing = await ActionProcess.run(URL(fileURLWithPath: "/nao/existe"), arguments: [])
        XCTAssertNotNil(missing.launchError)
    }
}
