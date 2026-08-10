// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimbreCanvas",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TimbreCanvas", targets: ["TimbreCanvas"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            revision: "70eff261d7f462cad1fff51e05bcc74aa0b0f420"
        ),
    ],
    targets: [
        .executableTarget(
            name: "TimbreCanvas",
            path: "Sources/TimbreCanvas",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TimbreCanvasTests",
            dependencies: [
                "TimbreCanvas",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/TimbreCanvasTests",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
