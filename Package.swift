// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TransManga",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TransMangaCore", targets: ["TransMangaCore"]),
        .executable(name: "TransManga", targets: ["TransManga"])
    ],
    targets: [
        .target(
            name: "TransMangaCore",
            path: "Sources/TransMangaCore"
        ),
        .executableTarget(
            name: "TransManga",
            dependencies: ["TransMangaCore"],
            path: "Sources/TransMangaApp"
        ),
        .testTarget(
            name: "TransMangaTests",
            dependencies: ["TransMangaCore"],
            path: "Tests/TransMangaTests"
        )
    ]
)
