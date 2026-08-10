import Foundation
import Testing
@testable import TimbreCanvas

@Test(.timeLimit(.minutes(1)))
@MainActor
func cancellingARealWorkerProcessTerminatesAndClassifiesTheExit() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-worker-process-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }
    let package = root.appending(path: "RuntimeHost/timbrecanvas_runtime", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
    try Data().write(to: package.appending(path: "__init__.py"))
    try Data(
        """
        import sys
        import time

        for _line in sys.stdin:
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
    let client = WorkerClient(installation: installation)

    let exitResult: Result<WorkerProcessExit, any Error> = await withCheckedContinuation { continuation in
        client.onExit = { continuation.resume(returning: .success($0)) }
        do {
            try client.start()
            client.cancelForRestart()
        } catch {
            continuation.resume(returning: .failure(error))
        }
    }

    #expect(try exitResult.get() == .cancelled)
    #expect(!client.isRunning)
}

@Test @MainActor func processOutputSessionRejectsStaleMessagesAndTermination() throws {
    var session = WorkerProcessSession()
    let oldGeneration = UUID()
    let newGeneration = UUID()
    session.begin(oldGeneration)
    #expect(session.append(Data(#"{"type":"result""#.utf8), for: oldGeneration).isEmpty)

    session.begin(newGeneration)
    #expect(session.append(Data("}\n".utf8), for: oldGeneration).isEmpty)
    let line = #"{"type":"result","requestID":"new"}"#
    #expect(session.append(Data("\(line)\n".utf8), for: newGeneration) == [line])
    let staleFinish = session.finish(oldGeneration)
    let currentFinish = session.finish(newGeneration)
    #expect(!staleFinish)
    #expect(currentFinish)
}

@Test(.timeLimit(.minutes(1)))
@MainActor
func shutdownOverridesCancellationForARealTerminatingProcess() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-worker-shutdown-race-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }
    let package = root.appending(path: "RuntimeHost/timbrecanvas_runtime", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
    try Data().write(to: package.appending(path: "__init__.py"))
    try Data("import time\ntime.sleep(60)\n".utf8).write(to: package.appending(path: "main.py"))
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
    let client = WorkerClient(installation: installation)

    let exit = await withCheckedContinuation { continuation in
        client.onExit = { continuation.resume(returning: $0) }
        do {
            try client.start()
            client.cancelForRestart()
            client.shutdown()
        } catch {
            Issue.record("Worker launch failed: \(error)")
            continuation.resume(returning: .unexpected(-1))
        }
    }

    #expect(exit == .shutdown)
    #expect(!client.isRunning)
}
