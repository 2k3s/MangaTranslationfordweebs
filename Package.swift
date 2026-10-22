// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MangaLens",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MangaLens", targets: ["MangaLens"])
    ],
    targets: [
        .executableTarget(
            name: "MangaLens",
            path: "Sources/MangaLens"
        )
    ]
)
