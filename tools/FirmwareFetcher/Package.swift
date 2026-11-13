// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FirmwareFetcher",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "FirmwareFetcher")
    ]
)
