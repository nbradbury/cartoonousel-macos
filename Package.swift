// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cartoonousel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cartoonousel",
            path: "Sources/Cartoonousel",
            resources: [.copy("Resources/Fonts"), .copy("Resources/AppIcon.icns"), .copy("Resources/SampleStrips"),
                        .copy("Resources/Cartoonizer.mlmodelc"), .copy("Resources/Cartoonizer-LICENSE.txt")]
        )
    ]
)
