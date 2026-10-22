// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yoz",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Yoz", targets: ["Yoz"])],
    dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")],
    targets: [
        .target(name: "TransliterationCore"),
        .target(name: "AssistantCore", dependencies: ["SwiftSoup"]),
        .executableTarget(name: "Yoz", dependencies: ["TransliterationCore", "AssistantCore"], resources: [.copy("Resources")]),
        .testTarget(name: "TransliterationCoreTests", dependencies: ["TransliterationCore"]),
        .testTarget(name: "AssistantCoreTests", dependencies: ["AssistantCore"])
    ]
)
