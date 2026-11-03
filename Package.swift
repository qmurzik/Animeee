// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WatchCore", products: [.library(name: "WatchCore", targets: ["WatchCore"])], targets: [
    .target(name: "WatchCore", path: "AnimeApp", exclude: ["ShikimoriVideos.swift", "Assets.xcassets", "AnimeApp.swift", "Info.plist", "Experience.swift", "BrowseScreens.swift", "WatchPlayer.swift", "LibraryScreen.swift"], sources: ["WatchCore.swift", "ExternalVideo.swift"]),
    .testTarget(name: "WatchCoreTests", dependencies: ["WatchCore"], path: "Tests/WatchCoreTests")
])
