import Foundation
import Testing
@testable import TimbreCanvas

@Test func bundledExecutableResolvesProjectRoot() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appending(path: ".build/runtime-path-test", directoryHint: .isDirectory)
    let executable = root.appending(path: "dist/TimbreCanvas.app/Contents/MacOS/TimbreCanvas")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: root.appending(path: "pyproject.toml").path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root) }

    let resolved = RuntimePaths.projectRoot(
        environment: [:],
        executableURL: executable,
        currentDirectory: URL(fileURLWithPath: "/")
    )

    #expect(resolved == root.standardizedFileURL)
}

@Test func packagedAppCanResolveConfiguredProjectRootAfterBeingMoved() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appending(path: ".build/configured-runtime-path-test", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: root.appending(path: "pyproject.toml").path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root) }

    let resolved = RuntimePaths.projectRoot(
        environment: [:],
        executableURL: URL(fileURLWithPath: "/Applications/TimbreCanvas.app/Contents/MacOS/TimbreCanvas"),
        currentDirectory: URL(fileURLWithPath: "/"),
        configuredBundlePath: root.path
    )

    #expect(resolved == root.standardizedFileURL)
}
