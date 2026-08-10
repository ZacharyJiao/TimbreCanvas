import Foundation
import Testing
@testable import TimbreCanvas

@Test func defaultInstallationUsesApplicationSupportAndBundledWorker() throws {
    let home = URL(fileURLWithPath: "/tmp/timbrecanvas-test-home", isDirectory: true)
    let resources = URL(
        fileURLWithPath: "/Applications/TimbreCanvas.app/Contents/Resources",
        isDirectory: true
    )

    let installation = try RuntimeInstallation.resolve(
        environment: [:],
        homeDirectory: home,
        bundleResourceRoot: resources
    )

    let support = home.appending(
        path: "Library/Application Support/TimbreCanvas",
        directoryHint: .isDirectory
    )
    #expect(installation.supportRoot == support)
    #expect(installation.pythonURL == support.appending(path: "Runtime/.venv/bin/python"))
    #expect(installation.modelURL == support.appending(path: "Models/IndexTTS-2-MLX-8bit"))
    #expect(installation.workerModuleRoot == resources.appending(path: "RuntimeHost"))
    #expect(installation.voiceRoot == support.appending(path: "Voices"))
    #expect(installation.presetRoot == support.appending(path: "Presets"))
    #expect(installation.configURL == support.appending(path: "config.json"))
}

@Test func environmentOverrideRelocatesPrivateRuntimeData() throws {
    let override = "/Volumes/ExternalAI/TimbreCanvas"
    let installation = try RuntimeInstallation.resolve(
        environment: ["TIMBRECANVAS_RUNTIME_ROOT": override],
        homeDirectory: URL(fileURLWithPath: "/tmp/unused", isDirectory: true),
        bundleResourceRoot: URL(fileURLWithPath: "/Applications/TimbreCanvas.app/Contents/Resources")
    )

    #expect(installation.supportRoot.path == override)
    #expect(installation.pythonURL.path == "\(override)/Runtime/.venv/bin/python")
    #expect(installation.modelURL.path == "\(override)/Models/IndexTTS-2-MLX-8bit")
}

@Test func configurationFileCanPointToExternalRuntimeAssets() throws {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-runtime-configuration-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: home) }

    let support = home.appending(
        path: "Library/Application Support/TimbreCanvas",
        directoryHint: .isDirectory
    )
    try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
    let configuration = """
    {
      "schemaVersion": 1,
      "pythonPath": "/Volumes/AI/Runtime/.venv/bin/python",
      "modelPath": "/Volumes/AI/Models/IndexTTS-2-MLX-8bit",
      "voiceRoot": "/Volumes/AI/Voices",
      "presetRoot": "/Volumes/AI/Presets",
      "cacheRoot": "/Volumes/AI/Cache"
    }
    """
    try Data(configuration.utf8).write(to: support.appending(path: "config.json"))

    let installation = try RuntimeInstallation.resolve(
        environment: [:],
        homeDirectory: home,
        bundleResourceRoot: URL(fileURLWithPath: "/Applications/TimbreCanvas.app/Contents/Resources")
    )

    #expect(installation.pythonURL.path == "/Volumes/AI/Runtime/.venv/bin/python")
    #expect(installation.modelURL.path == "/Volumes/AI/Models/IndexTTS-2-MLX-8bit")
    #expect(installation.voiceRoot.path == "/Volumes/AI/Voices")
    #expect(installation.presetRoot.path == "/Volumes/AI/Presets")
    #expect(installation.cacheRoot.path == "/Volumes/AI/Cache")
}

@Test @MainActor func workerLaunchUsesConfiguredPythonAndBundledModule() throws {
    let support = URL(fileURLWithPath: "/Volumes/AI/TimbreCanvas", isDirectory: true)
    let resources = URL(fileURLWithPath: "/Applications/TimbreCanvas.app/Contents/Resources")
    let installation = try RuntimeInstallation.resolve(
        environment: ["TIMBRECANVAS_RUNTIME_ROOT": support.path],
        homeDirectory: URL(fileURLWithPath: "/tmp/unused"),
        bundleResourceRoot: resources
    )

    let configuration = WorkerClient.launchConfiguration(
        for: installation,
        baseEnvironment: ["PATH": "/usr/bin", "PYTHONPATH": "/existing/python"]
    )

    #expect(configuration.executableURL == support.appending(path: "Runtime/.venv/bin/python"))
    #expect(configuration.arguments == ["-m", "timbrecanvas_runtime.main"])
    #expect(configuration.currentDirectoryURL == support)
    #expect(configuration.environment["PYTHONPATH"] == "\(resources.path)/RuntimeHost:/existing/python")
    #expect(configuration.environment["HF_HOME"] == "\(support.path)/Cache/huggingface")
    #expect(configuration.environment["TIMBRECANVAS_MODEL_PATH"] == "\(support.path)/Models/IndexTTS-2-MLX-8bit")
    #expect(configuration.environment["PYTHONDONTWRITEBYTECODE"] == "1")
}

@Test func unsupportedConfigurationSchemaIsRejected() throws {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-unsupported-schema-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: home) }
    let support = home.appending(
        path: "Library/Application Support/TimbreCanvas",
        directoryHint: .isDirectory
    )
    try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":99}"#.utf8).write(to: support.appending(path: "config.json"))

    #expect(throws: RuntimeInstallation.Error.unsupportedSchema(99)) {
        try RuntimeInstallation.resolve(
            environment: [:],
            homeDirectory: home,
            bundleResourceRoot: URL(fileURLWithPath: "/Applications/TimbreCanvas.app/Contents/Resources")
        )
    }
}
