// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Diag",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.4.10")],
    targets: [.executableTarget(name: "Diag", dependencies: ["YouTubeKit"])]
)
