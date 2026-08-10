import Combine
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    private static let logger = Logger(
        subsystem: AppIdentity.bundleIdentifier,
        category: "Inference"
    )
    @Published private(set) var worker = WorkerStateStore()
    @Published private(set) var engines: [EngineCapability] = []
    @Published private(set) var lastError: WorkerFailure?
    @Published private(set) var progress = 0.0
    @Published private(set) var progressStage = ""

    let projectRoot: URL
    private let client: WorkerClient
    private var voiceContinuations: [String: CheckedContinuation<URL, any Error>] = [:]
    private var generationContinuations: [String: CheckedContinuation<URL, any Error>] = [:]

    init(projectRoot: URL = RuntimePaths.projectRoot()) {
        self.projectRoot = projectRoot
        client = WorkerClient(projectRoot: projectRoot)
        client.onMessage = { [weak self] message in self?.receive(message) }
        client.onUnexpectedExit = { [weak self] _ in self?.recoverIfPossible() }
    }

    var state: WorkerState { worker.state }
    var diagnostics: String { client.diagnostics }

    func startIfNeeded() {
        guard !client.isRunning else { return }
        Self.logger.info("Starting resident inference worker")
        worker.state = .starting
        lastError = nil
        do {
            try client.start()
            try client.send("ping")
            try client.send("list_engines")
            worker.beginModelLoad()
            try client.send(
                "load_model",
                payload: [
                    "engineID": .string("indextts2"),
                    "modelPath": .string(
                        projectRoot.appending(path: "runtime/models/IndexTTS-2-MLX-8bit").path
                    ),
                    "memoryLimitGB": .number(24),
                ]
            )
            Self.logger.info("Worker started; model load requested")
        } catch {
            Self.logger.error("Worker startup failed: \(error.localizedDescription, privacy: .public)")
            worker.state = .unavailable
            lastError = WorkerFailure(
                requestID: nil,
                code: "worker_start_failed",
                message: error.localizedDescription
            )
        }
    }

    func shutdown() {
        Self.logger.info("Stopping resident inference worker")
        client.shutdown()
    }

    func extractVoice(referenceURL: URL, speakerURL: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let requestID = try client.send(
                    "extract_voice",
                    payload: [
                        "referencePath": .string(referenceURL.path),
                        "outputPath": .string(speakerURL.path),
                    ]
                )
                voiceContinuations[requestID] = continuation
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func generate(
        draft: GenerationDraft,
        outputURL: URL,
        capability: EngineCapability?
    ) async throws -> URL {
        guard state == .ready else {
            throw WorkerFailure(
                requestID: nil,
                code: "engine_not_ready",
                message: "模型仍在准备，请稍候"
            )
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let payload = try draft.workerPayload(
                    outputURL: outputURL,
                    capability: capability
                )
                let requestID = try client.send("generate", payload: payload)
                generationContinuations[requestID] = continuation
                worker.beginGeneration()
                progress = 0
                progressStage = "preparing"
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func receive(_ message: WorkerMessage) {
        if case let .result(result) = message, let engines = result.engines {
            self.engines = engines
        }
        if case let .result(result) = message,
           let speakerPath = result.speakerPath,
           let continuation = voiceContinuations.removeValue(forKey: result.requestID) {
            continuation.resume(returning: URL(fileURLWithPath: speakerPath))
        }
        if case let .result(result) = message,
           let outputPath = result.outputPath,
           let continuation = generationContinuations.removeValue(forKey: result.requestID) {
            continuation.resume(returning: URL(fileURLWithPath: outputPath))
        }
        if case let .progress(_, progress, stage) = message {
            self.progress = progress
            progressStage = stage
        }
        if case let .error(error) = message {
            Self.logger.error("Worker error [\(error.code, privacy: .public)]: \(error.message, privacy: .public)")
            lastError = error
            if let requestID = error.requestID,
               let continuation = voiceContinuations.removeValue(forKey: requestID) {
                continuation.resume(throwing: error)
            }
            if let requestID = error.requestID,
               let continuation = generationContinuations.removeValue(forKey: requestID) {
                continuation.resume(throwing: error)
            }
        }
        if case let .ready(_, engineID) = message {
            Self.logger.info("Inference engine ready: \(engineID, privacy: .public)")
        }
        worker.receive(message)
    }

    private func recoverIfPossible() {
        Self.logger.error("Resident inference worker exited unexpectedly")
        if worker.handleUnexpectedExit() == .restart {
            Self.logger.info("Attempting one automatic worker restart")
            startIfNeeded()
        }
    }
}
