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

    let installation: RuntimeInstallation
    private let client: any WorkerClientProtocol
    private var voiceContinuations: [String: CheckedContinuation<URL, any Error>] = [:]
    private var generationContinuations: [String: CheckedContinuation<URL, any Error>] = [:]
    private var generationPartials: [String: URL] = [:]
    private var pendingPartialCleanup: Set<URL> = []
    private var desiredRunning = false

    init(
        installation: RuntimeInstallation = (try? RuntimeInstallation.resolve()) ?? .defaults(),
        client: (any WorkerClientProtocol)? = nil
    ) {
        self.installation = installation
        let client = client ?? WorkerClient(installation: installation)
        self.client = client
        client.onMessage = { [weak self] message in self?.receive(message) }
        client.onExit = { [weak self] exit in self?.handleWorkerExit(exit) }
    }

    var state: WorkerState { worker.state }
    var diagnostics: String { client.diagnostics }

    func startIfNeeded() {
        desiredRunning = true
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
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
                        installation.modelURL.path
                    ),
                    "memoryLimitGB": .number(24),
                ]
            )
            Self.logger.info("Worker started; model load requested")
        } catch {
            Self.logger.error("Worker startup failed: \(error.localizedDescription, privacy: .private)")
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
        desiredRunning = false
        failPendingRequests(
            with: WorkerFailure(
                requestID: nil,
                code: "worker_shutdown",
                message: "推理进程已关闭"
            )
        )
        client.shutdown()
    }

    func cancelGeneration() {
        guard !generationContinuations.isEmpty else { return }
        let failure = WorkerFailure(
            requestID: nil,
            code: "cancelled",
            message: "生成已取消"
        )
        failPendingRequests(with: failure)
        progress = 0
        progressStage = ""
        client.cancelForRestart()
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
                var payload = try draft.workerPayload(
                    outputURL: outputURL,
                    capability: capability
                )
                let partialToken = UUID().uuidString.lowercased()
                payload["partialToken"] = .string(partialToken)
                let requestID = try client.send("generate", payload: payload)
                generationContinuations[requestID] = continuation
                generationPartials[requestID] = outputURL.deletingLastPathComponent().appending(
                    path: ".timbrecanvas.\(partialToken).partial.wav"
                )
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
            generationPartials.removeValue(forKey: result.requestID)
            continuation.resume(returning: URL(fileURLWithPath: outputPath))
        }
        if case let .progress(_, progress, stage) = message {
            self.progress = progress
            progressStage = stage
        }
        if case let .error(error) = message {
            Self.logger.error("Worker error [\(error.code, privacy: .public)]: \(error.message, privacy: .private)")
            lastError = error
            if let requestID = error.requestID,
               let continuation = voiceContinuations.removeValue(forKey: requestID) {
                continuation.resume(throwing: error)
            }
            if let requestID = error.requestID,
               let continuation = generationContinuations.removeValue(forKey: requestID) {
                if let partial = generationPartials.removeValue(forKey: requestID) {
                    removePartialOutput(partial)
                }
                continuation.resume(throwing: error)
            }
        }
        if case let .ready(_, engineID) = message {
            Self.logger.info("Inference engine ready: \(engineID, privacy: .public)")
        }
        worker.receive(message)
    }

    private func handleWorkerExit(_ exit: WorkerProcessExit) {
        switch exit {
        case .shutdown:
            failPendingRequests(
                with: WorkerFailure(
                    requestID: nil,
                    code: "worker_shutdown",
                    message: "推理进程已关闭"
                )
            )
            cleanupPendingPartials()
        case .cancelled:
            cleanupPendingPartials()
            guard desiredRunning else { return }
            Self.logger.info("Restarting inference worker after cancellation")
            startWorkerIfNeeded()
        case let .unexpected(status):
            Self.logger.error("Resident inference worker exited unexpectedly [\(status, privacy: .public)]")
            failPendingRequests(
                with: WorkerFailure(
                    requestID: nil,
                    code: "worker_exited",
                    message: "推理进程意外退出，请重试"
                )
            )
            cleanupPendingPartials()
            if desiredRunning, worker.handleUnexpectedExit() == .restart {
                Self.logger.info("Attempting one automatic worker restart")
                startWorkerIfNeeded()
            } else if !desiredRunning {
                worker.state = .unavailable
            }
        }
    }

    private func failPendingRequests(with failure: WorkerFailure) {
        let voiceRequests = Array(voiceContinuations.values)
        let generationRequests = Array(generationContinuations.values)
        pendingPartialCleanup.formUnion(generationPartials.values)
        voiceContinuations.removeAll()
        generationContinuations.removeAll()
        generationPartials.removeAll()
        for continuation in voiceRequests {
            continuation.resume(throwing: failure)
        }
        for continuation in generationRequests {
            continuation.resume(throwing: failure)
        }
    }

    private func cleanupPendingPartials() {
        let outputs = pendingPartialCleanup
        pendingPartialCleanup.removeAll()
        for partial in outputs {
            removePartialOutput(partial)
        }
    }

    private func removePartialOutput(_ partial: URL) {
        try? FileManager.default.removeItem(at: partial)
    }
}
