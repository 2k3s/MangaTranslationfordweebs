// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TransManga",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TransManga", targets: ["TransManga"])
    ],
    targets: [
        .executableTarget(
            name: "TransManga",
            path: "Sources/TransManga"
        )
    ]
)
