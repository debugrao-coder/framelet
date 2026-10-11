// swift-tools-version: 5.9
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
// Architecture-specific builds must never link the host Rust library by accident.
let coreLibraryDirectory = ProcessInfo.processInfo.environment["FRAMELET_CORE_LIB_DIR"] ?? "\(root)/core/target/release"
let package = Package(name: "Framelet", platforms: [.macOS(.v14)], products: [.executable(name: "Framelet", targets: ["Framelet"])], targets: [.executableTarget(name: "Framelet", linkerSettings: [.unsafeFlags(["-L\(coreLibraryDirectory)"]), .linkedLibrary("framelet_core")])])
