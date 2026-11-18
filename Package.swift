// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iEdge",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "iEdge",
            path: "Sources/iEdge"
        ),
        .testTarget(
            name: "iEdgeTests",
            dependencies: ["iEdge"],
            path: "Tests/iEdgeTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
