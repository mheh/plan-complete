// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlanComplete",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PlanCompleteCore", targets: ["PlanCompleteCore"]),
        .executable(name: "plan-complete", targets: ["plan-complete"]),
    ],
    targets: [
        .target(name: "PlanCompleteCore"),
        .target(name: "PlanCompleteLSP", dependencies: ["PlanCompleteCore"]),
        .executableTarget(name: "plan-complete", dependencies: ["PlanCompleteCore", "PlanCompleteLSP"]),
        .testTarget(name: "PlanCompleteCoreTests", dependencies: ["PlanCompleteCore"]),
        .testTarget(name: "PlanCompleteLSPTests", dependencies: ["PlanCompleteLSP", "PlanCompleteCore"]),
    ]
)
