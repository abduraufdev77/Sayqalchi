// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yoz",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Yoz", targets: ["Yoz"])],
    targets: [
        .target(name: "TransliterationCore"),
        .executableTarget(name: "Yoz", dependencies: ["TransliterationCore"], resources: [.copy("Resources")]),
        .testTarget(name: "TransliterationCoreTests", dependencies: ["TransliterationCore"])
    ]
)
