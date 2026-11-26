// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacPad",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "MacPad",
            dependencies: ["SwiftTerm"],
            path: "Sources/MacPad"
        )
    ]
)
