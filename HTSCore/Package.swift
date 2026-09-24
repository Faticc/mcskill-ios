// swift-tools-version:5.9
import PackageDescription

// Launcher logic without UI: the McSkill gRPC API, session, caches and the log. The app target
// (project.yml) only draws it; the tests run on macOS with `swift test`.
let package = Package(
    name: "HTSCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "HTSCore", targets: ["HTSCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.27.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        // Generated at build time from the .proto files next to the configs (protoc from Homebrew,
        // see protocPath in the configs)
        .target(
            name: "McSkillProto",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            plugins: [
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf"),
                .plugin(name: "GRPCSwiftPlugin", package: "grpc-swift"),
            ]
        ),
        .target(
            name: "HTSCore",
            dependencies: [
                "McSkillProto",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "HTSCoreTests",
            dependencies: [
                "HTSCore",
                .product(name: "GRPC", package: "grpc-swift"),
            ]
        ),
    ]
)
