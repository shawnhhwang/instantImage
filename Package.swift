// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProjectLumina",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ProjectLumina", targets: ["ProjectLumina"])
    ],
    targets: [
        .executableTarget(
            name: "ProjectLumina",
            path: ".",
            exclude: [
                "SPEC.md",
                "TASK_LIST.MD",
                "README.md",
                "appsettings.json",
                "Initial Prompt.md",
                "build_app.sh",
                "build_arm64.sh",
                "build_intel.sh",
                "build_dual_versions.sh",
                "swap",
                "graphify-out",
                "wiki.md",
                "LICENSE",
                "ProjectLumina.app",
                "ProjectLumina-AppleSilicon.app",
                "ProjectLumina-Intel.app",
                "ProjectLumina-Universal.app"
            ],
            sources: [
                "App",
                "Domain",
                "Data",
                "Presentation",
                "Infrastructure"
            ],
            resources: [
                .copy("appsettings.json")
            ]
        )
    ]
)
