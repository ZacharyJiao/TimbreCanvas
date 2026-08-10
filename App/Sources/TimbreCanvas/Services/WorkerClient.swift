import Combine
import Foundation

struct WorkerProcessConfiguration: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL
    let environment: [String: String]
}

enum WorkerProcessExit: Equatable, Sendable {
    case cancelled
    case shutdown
    case unexpected(Int32)
}

struct WorkerProcessSession: Sendable {
    private var activeGeneration: UUID?
    private var outputBuffer = JSONLineBuffer()

    mutating func begin(_ generation: UUID) {
        activeGeneration = generation
        outputBuffer = JSONLineBuffer()
    }

    mutating func append(_ data: Data, for generation: UUID) -> [String] {
        guard activeGeneration == generation else { return [] }
        return outputBuffer.append(data)
    }

    func isActive(_ generation: UUID) -> Bool {
        activeGeneration == generation
    }

    mutating func finish(_ generation: UUID) -> Bool {
        guard activeGeneration == generation else { return false }
        activeGeneration = nil
        outputBuffer = JSONLineBuffer()
        return true
    }
}

@MainActor
protocol WorkerClientProtocol: AnyObject {
    var isRunning: Bool { get }
    var diagnostics: String { get }
    var onMessage: ((WorkerMessage) -> Void)? { get set }
    var onExit: ((WorkerProcessExit) -> Void)? { get set }

    func start() throws
    @discardableResult
    func send(_ name: String, payload: [String: JSONValue]) throws -> String
    func shutdown()
    func cancelForRestart()
}

extension WorkerClientProtocol {
    @discardableResult
    func send(_ name: String) throws -> String {
        try send(name, payload: [:])
    }
}

@MainActor
final class WorkerClient: ObservableObject, WorkerClientProtocol {
    enum ClientError: LocalizedError {
        case alreadyRunning
        case pythonMissing(URL)
        case workerUnavailable

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "推理进程已经在运行"
            case let .pythonMissing(path): "找不到 Python 运行环境：\(path.path)"
            case .workerUnavailable: "推理进程不可用"
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var diagnostics = ""

    var onMessage: ((WorkerMessage) -> Void)?
    var onExit: ((WorkerProcessExit) -> Void)?

    let installation: RuntimeInstallation
    private var process: Process?
    private var inputHandle: FileHandle?
    private var session = WorkerProcessSession()
    private var requestedExit: WorkerProcessExit?

    init(installation: RuntimeInstallation) {
        self.installation = installation
    }

    func start() throws {
        guard process == nil else { throw ClientError.alreadyRunning }
        let configuration = Self.launchConfiguration(for: installation)
        guard FileManager.default.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw ClientError.pythonMissing(configuration.executableURL)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let child = Process()
        let generation = UUID()
        session.begin(generation)
        child.executableURL = configuration.executableURL
        child.arguments = configuration.arguments
        child.currentDirectoryURL = configuration.currentDirectoryURL
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = errorPipe
        child.environment = configuration.environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consumeOutput(data, generation: generation) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consumeDiagnostics(data, generation: generation) }
        }
        child.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.session.finish(generation) else { return }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                let exit = self.requestedExit ?? .unexpected(process.terminationStatus)
                self.requestedExit = nil
                self.isRunning = false
                self.process = nil
                self.inputHandle = nil
                self.onExit?(exit)
            }
        }

        do {
            try child.run()
        } catch {
            _ = session.finish(generation)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        requestedExit = nil
        process = child
        inputHandle = inputPipe.fileHandleForWriting
        isRunning = true
    }

    @discardableResult
    func send(_ name: String, payload: [String: JSONValue] = [:]) throws -> String {
        guard isRunning, let inputHandle else { throw ClientError.workerUnavailable }
        let requestID = UUID().uuidString.lowercased()
        var data = try WorkerJSONCodec.encode(
            WorkerCommand(name: name, requestID: requestID, payload: payload)
        )
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
        return requestID
    }

    func shutdown() {
        guard let process else {
            inputHandle?.closeFile()
            inputHandle = nil
            isRunning = false
            return
        }
        requestedExit = .shutdown
        if isRunning {
            _ = try? send("shutdown")
        }
        inputHandle?.closeFile()
        inputHandle = nil
        isRunning = false
        if process.isRunning {
            process.terminate()
        }
    }

    func cancelForRestart() {
        guard let process else {
            onExit?(.cancelled)
            return
        }
        requestedExit = .cancelled
        inputHandle?.closeFile()
        inputHandle = nil
        isRunning = false
        process.terminate()
    }

    private func consumeOutput(_ data: Data, generation: UUID) {
        for line in session.append(data, for: generation) {
            do {
                onMessage?(try WorkerJSONCodec.decode(Data(line.utf8)))
            } catch {
                diagnostics += "协议解析失败：\(error.localizedDescription)\n"
            }
        }
    }

    private func consumeDiagnostics(_ data: Data, generation: UUID) {
        guard session.isActive(generation) else { return }
        if let text = String(data: data, encoding: .utf8) {
            diagnostics += text
        }
    }

    static func launchConfiguration(
        for installation: RuntimeInstallation,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> WorkerProcessConfiguration {
        var environment = baseEnvironment
        let huggingFace = installation.cacheRoot.appending(path: "huggingface")
        let existingPythonPath = environment["PYTHONPATH"]
        environment["PYTHONPATH"] = [installation.workerModuleRoot.path, existingPythonPath]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        environment["TIMBRECANVAS_SUPPORT_ROOT"] = installation.supportRoot.path
        environment["TIMBRECANVAS_MODEL_PATH"] = installation.modelURL.path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["HF_HOME"] = huggingFace.path
        environment["HF_HUB_CACHE"] = huggingFace.appending(path: "hub").path
        environment["TRANSFORMERS_CACHE"] = huggingFace.appending(path: "transformers").path
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_XET"] = "1"
        environment["UV_CONCURRENT_DOWNLOADS"] = "1"
        return WorkerProcessConfiguration(
            executableURL: installation.pythonURL,
            arguments: ["-m", "timbrecanvas_runtime.main"],
            currentDirectoryURL: installation.supportRoot,
            environment: environment
        )
    }
}
