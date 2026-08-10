import Combine
import Foundation

@MainActor
final class WorkerClient: ObservableObject {
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
    var onUnexpectedExit: ((Int32) -> Void)?

    let projectRoot: URL
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = JSONLineBuffer()

    init(projectRoot: URL) {
        self.projectRoot = projectRoot.standardizedFileURL
    }

    func start() throws {
        guard process == nil else { throw ClientError.alreadyRunning }
        let python = projectRoot.appending(path: ".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw ClientError.pythonMissing(python)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let child = Process()
        child.executableURL = python
        child.arguments = ["-m", "runtime.worker.main"]
        child.currentDirectoryURL = projectRoot
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = errorPipe
        child.environment = workerEnvironment()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consumeOutput(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consumeDiagnostics(data) }
        }
        child.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRunning = false
                self.process = nil
                self.inputHandle = nil
                if process.terminationStatus != 0 {
                    self.onUnexpectedExit?(process.terminationStatus)
                }
            }
        }

        try child.run()
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
        if isRunning {
            _ = try? send("shutdown")
        }
        inputHandle?.closeFile()
        process = nil
        inputHandle = nil
        isRunning = false
    }

    private func consumeOutput(_ data: Data) {
        for line in outputBuffer.append(data) {
            do {
                onMessage?(try WorkerJSONCodec.decode(Data(line.utf8)))
            } catch {
                diagnostics += "协议解析失败：\(error.localizedDescription)\n"
            }
        }
    }

    private func consumeDiagnostics(_ data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            diagnostics += text
        }
    }

    private func workerEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let huggingFace = projectRoot.appending(path: "runtime/cache/huggingface")
        environment["INDEXTTS_PROJECT_ROOT"] = projectRoot.path
        environment["HF_HOME"] = huggingFace.path
        environment["HF_HUB_CACHE"] = huggingFace.appending(path: "hub").path
        environment["TRANSFORMERS_CACHE"] = huggingFace.appending(path: "transformers").path
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_XET"] = "1"
        environment["UV_CONCURRENT_DOWNLOADS"] = "1"
        return environment
    }
}

