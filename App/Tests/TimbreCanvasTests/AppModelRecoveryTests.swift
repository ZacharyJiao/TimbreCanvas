import Foundation
import Testing
@testable import TimbreCanvas

@MainActor
private final class TestWorkerClient: WorkerClientProtocol {
    var isRunning = false
    var diagnostics = ""
    var onMessage: ((WorkerMessage) -> Void)?
    var onExit: ((WorkerProcessExit) -> Void)?
    private(set) var sentCommands: [String] = []
    private(set) var sentPayloads: [[String: JSONValue]] = []
    private(set) var startCount = 0
    private(set) var cancellationCount = 0
    var delaysCancellationExit = false

    func start() throws {
        startCount += 1
        isRunning = true
    }

    func send(_ name: String, payload: [String: JSONValue]) throws -> String {
        sentCommands.append(name)
        sentPayloads.append(payload)
        return "\(name)-\(sentCommands.count)"
    }

    func shutdown() {
        isRunning = false
        onExit?(.shutdown)
    }

    func cancelForRestart() {
        cancellationCount += 1
        isRunning = false
        if !delaysCancellationExit {
            onExit?(.cancelled)
        }
    }

    func completeDelayedCancellation() {
        onExit?(.cancelled)
    }

    func emit(_ message: WorkerMessage) {
        onMessage?(message)
    }

    func exitUnexpectedly(status: Int32) {
        isRunning = false
        onExit?(.unexpected(status))
    }
}

@MainActor
private func readyModel() throws -> (AppModel, TestWorkerClient, URL) {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "timbrecanvas-worker-recovery-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let client = TestWorkerClient()
    let installation = RuntimeInstallation.defaults(
        environment: ["TIMBRECANVAS_RUNTIME_ROOT": root.path],
        homeDirectory: root,
        bundleResourceRoot: root.appending(path: "Resources")
    )
    let model = AppModel(installation: installation, client: client)
    model.startIfNeeded()
    client.emit(.ready(requestID: "load-model", engineID: "indextts2"))
    return (model, client, root)
}

private func draft(in root: URL) throws -> GenerationDraft {
    let reference = root.appending(path: "fixture.wav")
    let speaker = root.appending(path: "fixture.npz")
    try Data().write(to: reference)
    try Data().write(to: speaker)
    return GenerationDraft(
        text: "synthetic recovery fixture",
        voice: VoiceProfile(
            id: "fixture",
            engineID: "indextts2",
            profileVersion: 1,
            name: "Synthetic Fixture",
            kind: .custom,
            referencePath: reference.path,
            speakerPath: speaker.path,
            createdAt: "2026-01-01T00:00:00Z",
            note: ""
        )
    )
}

@MainActor
private func waitForGenerate(_ client: TestWorkerClient) async {
    for _ in 0..<100 where !client.sentCommands.contains("generate") {
        await Task.yield()
    }
}

@Test @MainActor func unexpectedWorkerExitFailsPendingGenerationBeforeRestart() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    let generation = Task {
        try await model.generate(
            draft: try draft(in: root),
            outputURL: root.appending(path: "result.wav"),
            capability: nil
        )
    }
    await waitForGenerate(client)

    client.exitUnexpectedly(status: 9)

    do {
        _ = try await generation.value
        Issue.record("A crashed worker left generation awaiting a result")
    } catch let failure as WorkerFailure {
        #expect(failure.code == "worker_exited")
    }
    #expect(client.startCount == 2)
}

@Test @MainActor func cancellationFailsGenerationAndRestartsResidentWorker() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    let generation = Task {
        try await model.generate(
            draft: try draft(in: root),
            outputURL: root.appending(path: "result.wav"),
            capability: nil
        )
    }
    await waitForGenerate(client)

    model.cancelGeneration()

    do {
        _ = try await generation.value
        Issue.record("Cancellation left generation awaiting a result")
    } catch let failure as WorkerFailure {
        #expect(failure.code == "cancelled")
    }
    #expect(client.cancellationCount == 1)
    #expect(client.startCount == 2)
}

@Test @MainActor func userCancellationReturnsComposerToIdleWithoutErrorAlert() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    let suiteName = "TimbreCanvas.CancellationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let generation = GenerationStore(defaults: defaults)
    let voice = try #require(try draft(in: root).voice)
    generation.text = "synthetic cancellation fixture"
    generation.outputDirectory = root
    let task = Task {
        await generation.generate(voice: voice, capability: nil, appModel: model)
    }
    await waitForGenerate(client)

    model.cancelGeneration()
    await task.value

    #expect(!generation.isGenerating)
    #expect(generation.errorMessage == nil)
}

@Test @MainActor func crashedWorkerReturnsComposerToIdleWithRetryableMessage() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    let suiteName = "TimbreCanvas.CrashRecoveryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let generation = GenerationStore(defaults: defaults)
    let voice = try #require(try draft(in: root).voice)
    generation.text = "synthetic crash fixture"
    generation.outputDirectory = root
    let task = Task {
        await generation.generate(voice: voice, capability: nil, appModel: model)
    }
    await waitForGenerate(client)

    client.exitUnexpectedly(status: 9)
    await task.value

    #expect(!generation.isGenerating)
    #expect(generation.errorMessage == "推理进程意外退出，请重试")
}

@Test @MainActor func shutdownFailsPendingGenerationWithoutRestartingWorker() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }

    await confirmation("pending generation resumed during shutdown") { resumed in
        Task {
            do {
                _ = try await model.generate(
                    draft: try draft(in: root),
                    outputURL: root.appending(path: "result.wav"),
                    capability: nil
                )
                Issue.record("Shutdown returned a generation result")
            } catch let failure as WorkerFailure {
                #expect(failure.code == "worker_shutdown")
            } catch {
                Issue.record("Shutdown returned an unexpected error: \(error)")
            }
            resumed()
        }
        await waitForGenerate(client)
        model.shutdown()
        for _ in 0..<100 {
            await Task.yield()
        }
    }

    #expect(client.startCount == 1)
}

@Test @MainActor func shutdownFailsPendingVoiceExtractionWithoutRestartingWorker() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    let reference = root.appending(path: "reference.wav")
    try Data().write(to: reference)

    await confirmation("pending voice extraction resumed during shutdown") { resumed in
        Task {
            do {
                _ = try await model.extractVoice(
                    referenceURL: reference,
                    speakerURL: root.appending(path: "speaker.npz")
                )
                Issue.record("Shutdown returned a voice profile")
            } catch let failure as WorkerFailure {
                #expect(failure.code == "worker_shutdown")
            } catch {
                Issue.record("Shutdown returned an unexpected error: \(error)")
            }
            resumed()
        }
        for _ in 0..<100 where !client.sentCommands.contains("extract_voice") {
            await Task.yield()
        }
        model.shutdown()
        for _ in 0..<100 {
            await Task.yield()
        }
    }

    #expect(client.startCount == 1)
}

@Test @MainActor func shutdownDuringCancellationNeverRestartsWorker() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    client.delaysCancellationExit = true
    let generation = Task {
        try await model.generate(
            draft: try draft(in: root),
            outputURL: root.appending(path: "result.wav"),
            capability: nil
        )
    }
    await waitForGenerate(client)

    model.cancelGeneration()
    model.shutdown()
    client.completeDelayedCancellation()
    _ = try? await generation.value

    #expect(client.startCount == 1)
}

@Test @MainActor func cancellationRemovesOnlyTheActiveOutputsPartialFiles() async throws {
    let (model, client, root) = try readyModel()
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appending(path: "你好，世界.wav")
    let generation = Task {
        try await model.generate(
            draft: try draft(in: root),
            outputURL: output,
            capability: nil
        )
    }
    await waitForGenerate(client)
    let token = try #require(client.sentPayloads.last?["partialToken"])
    let tokenValue: String
    if case let .string(value) = token {
        tokenValue = value
    } else {
        Issue.record("Generation did not send a string partial token")
        return
    }
    let partial = root.appending(path: ".timbrecanvas.\(tokenValue).partial.wav")
    let unrelated = root.appending(
        path: ".timbrecanvas.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.partial.wav"
    )
    try Data("partial".utf8).write(to: partial)
    try Data("unrelated".utf8).write(to: unrelated)

    model.cancelGeneration()
    _ = try? await generation.value

    #expect(!FileManager.default.fileExists(atPath: partial.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}

@Test(.timeLimit(.minutes(1)))
@MainActor
func realWorkerCancellationRemovesItsScopedPartialOutput() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-real-partial-cleanup-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }
    let package = root.appending(path: "RuntimeHost/timbrecanvas_runtime", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
    try Data().write(to: package.appending(path: "__init__.py"))
    try Data(
        """
        import json
        import pathlib
        import sys
        import time

        for line in sys.stdin:
            command = json.loads(line)
            if command["command"] == "load_model":
                print(json.dumps({
                    "type": "ready",
                    "requestID": command["requestID"],
                    "engineID": "indextts2",
                }), flush=True)
            elif command["command"] == "generate":
                output = pathlib.Path(command["payload"]["outputPath"])
                token = command["payload"]["partialToken"]
                partial = output.parent / f".timbrecanvas.{token}.partial.wav"
                partial.write_bytes(b"synthetic partial")
                time.sleep(60)
        """.utf8
    ).write(to: package.appending(path: "main.py"))
    let support = root.appending(path: "Support", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
    let installation = RuntimeInstallation(
        supportRoot: support,
        pythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
        modelURL: root.appending(path: "Model"),
        workerModuleRoot: root.appending(path: "RuntimeHost"),
        voiceRoot: root.appending(path: "Voices"),
        presetRoot: root.appending(path: "Presets"),
        configURL: support.appending(path: "config.json"),
        cacheRoot: root.appending(path: "Cache")
    )
    let model = AppModel(installation: installation, client: WorkerClient(installation: installation))
    model.startIfNeeded()
    for _ in 0..<1_000 where model.state != .ready {
        try await Task.sleep(for: .milliseconds(2))
    }
    #expect(model.state == .ready)
    let output = root.appending(path: "result.wav")
    let partialPrefix = ".timbrecanvas."
    let generation = Task {
        try await model.generate(
            draft: try draft(in: root),
            outputURL: output,
            capability: nil
        )
    }
    var partial: URL?
    for _ in 0..<1_000 where partial == nil {
        partial = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).first {
            $0.lastPathComponent.hasPrefix(partialPrefix)
                && $0.lastPathComponent.hasSuffix(".partial.wav")
        }
        try await Task.sleep(for: .milliseconds(2))
    }
    let createdPartial = try #require(partial)
    #expect(fileManager.fileExists(atPath: createdPartial.path))

    model.cancelGeneration()
    _ = try? await generation.value
    for _ in 0..<1_000 where fileManager.fileExists(atPath: createdPartial.path) {
        try await Task.sleep(for: .milliseconds(2))
    }

    #expect(!fileManager.fileExists(atPath: createdPartial.path))
    model.shutdown()
}
