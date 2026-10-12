// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HiFace",
    platforms: [.iOS(.v15)],
    products: [.library(name: "HiFace", targets: ["HiFace", "HiFaceNative"])],
    targets: [
        .binaryTarget(name: "HiFace", path: "HiFace.xcframework"),
        .binaryTarget(name: "HiFaceNative", path: "HiFaceNative.xcframework")
    ]
)
