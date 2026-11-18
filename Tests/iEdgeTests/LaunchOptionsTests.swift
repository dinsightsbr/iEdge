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

    func testSchemeDefaultsToLightOnlyForSnapshots() {
        XCTAssertNil(parse("--demo").schemeOverride)
        XCTAssertEqual(parse("--demo").scheme, .light)
        XCTAssertEqual(parse("--scheme dark").schemeOverride, .dark)
        XCTAssertNil(parse("--scheme sepia").schemeOverride)
    }

    func testBackdrop() {
        XCTAssertFalse(parse("--demo").backdrop)
        let options = parse("--demo --backdrop --scheme dark --show left --pin --flyout")
        XCTAssertTrue(options.backdrop)
        XCTAssertEqual(options.schemeOverride, .dark)
        XCTAssertEqual(options.show, .left)
        XCTAssertTrue(options.flyout)
        // A flag right after --backdrop is still read as its own flag.
        XCTAssertEqual(parse("--backdrop --settings bordas").settings, .bordas)
    }

    @MainActor
    func testBackdropPalettes() {
        let light = BackdropWindow.gradient(dark: false)
        let dark = BackdropWindow.gradient(dark: true)
        XCTAssertGreaterThanOrEqual(light.count, 2)
        XCTAssertEqual(light.count, dark.count)
        func luminance(_ c: (red: Double, green: Double, blue: Double)) -> Double {
            0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        }
        XCTAssertTrue(light.allSatisfy { luminance($0) > 0.7 })
        XCTAssertTrue(dark.allSatisfy { luminance($0) < 0.3 })
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
