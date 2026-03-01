// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonoText",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "SonoText",
            targets: ["SonoText"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "SonoText",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/SonoText"
        )
    ]
)
