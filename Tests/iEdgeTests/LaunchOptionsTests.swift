import XCTest
@testable import iEdge

final class LaunchOptionsTests: XCTestCase {
    private func parse(_ line: String) -> LaunchOptions {
        LaunchOptions(arguments: ["iEdge"] + line.split(separator: " ").map(String.init))
    }

    func testNoFlags() {
        XCTAssertEqual(parse(""), LaunchOptions())
    }

    func testSidebarFlags() {
        let options = parse("--demo --show right --pin --hover 0.3 --flyout --frame-file /tmp/f")
        XCTAssertTrue(options.demo)
        XCTAssertEqual(options.show, .right)
        XCTAssertTrue(options.pin)
        XCTAssertEqual(options.hover, 0.3)
        XCTAssertTrue(options.flyout)
        XCTAssertEqual(options.frameFile, "/tmp/f")
        XCTAssertTrue(options.opensUIAtLaunch)
    }

    func testHoverIsClamped() {
        XCTAssertEqual(parse("--hover 3").hover, 1)
        XCTAssertNil(parse("--hover x").hover)
    }

    func testSettingsTabIsOptional() {
        XCTAssertEqual(parse("--settings").settings, .itens)
        XCTAssertEqual(parse("--settings --demo").settings, .itens)
        XCTAssertEqual(parse("--settings capturas").settings, .capturas)
        XCTAssertNil(parse("--demo").settings)
    }

    func testSnapshot() {
        let options = parse("--snapshot sidebar --out a.png --scheme dark --demo")
        XCTAssertEqual(options.snapshot, "sidebar")
        XCTAssertEqual(options.snapshotOut, "a.png")
        XCTAssertEqual(options.scheme, .dark)
        XCTAssertEqual(parse("--snapshot list").snapshot, "list")
    }

    @MainActor
    func testSnapshotCatalogHasOneEntryPerPiece() {
        let names = SnapshotCatalog.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains("sidebar"))
        XCTAssertTrue(names.contains("clipboard"))
        XCTAssertTrue(names.contains("settings-itens"))
    }
}
