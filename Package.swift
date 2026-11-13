// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kkok",
    platforms: [.macOS(.v14)],
    targets: [
        // 앱 본체. 모델(Model)·그리기(Render)는 AppKit 화면 코드와 분리해 테스트한다.
        .executableTarget(
            name: "Kkok",
            path: "Sources/Kkok",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "KkokTests",
            dependencies: ["Kkok"],
            path: "Tests/KkokTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
