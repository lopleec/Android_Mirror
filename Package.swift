// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AndroidMirror",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AndroidMirror", targets: ["AndroidMirror"])],
    targets: [
        .executableTarget(name: "AndroidMirror", resources: [.process("Resources"), .process("Localization")]),
        .testTarget(name: "AndroidMirrorTests", dependencies: ["AndroidMirror"], resources: [.copy("Fixtures")])
    ]
)
