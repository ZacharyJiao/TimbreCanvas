import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct WorkerCommand: Codable, Equatable, Sendable {
    let name: String
    let requestID: String
    let payload: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case name = "command"
        case requestID
        case payload
    }
}

struct WorkerFailure: Codable, Equatable, Error, Sendable {
    let requestID: String?
    let code: String
    let message: String
}

struct WorkerResult: Equatable, Sendable {
    let requestID: String
    let status: String?
    let processID: Int?
    let engines: [EngineCapability]?
    let outputPath: String?
    let speakerPath: String?
    let shutdown: Bool?
    let cancelled: Bool?

    init(
        requestID: String,
        status: String? = nil,
        processID: Int? = nil,
        engines: [EngineCapability]? = nil,
        outputPath: String? = nil,
        speakerPath: String? = nil,
        shutdown: Bool? = nil,
        cancelled: Bool? = nil
    ) {
        self.requestID = requestID
        self.status = status
        self.processID = processID
        self.engines = engines
        self.outputPath = outputPath
        self.speakerPath = speakerPath
        self.shutdown = shutdown
        self.cancelled = cancelled
    }
}

enum WorkerMessage: Equatable, Sendable {
    case result(WorkerResult)
    case ready(requestID: String, engineID: String)
    case progress(requestID: String, progress: Double, stage: String)
    case error(WorkerFailure)
}

private struct WorkerEnvelope: Decodable {
    let type: String
    let requestID: String?
    let code: String?
    let message: String?
    let engineID: String?
    let progress: Double?
    let stage: String?
    let status: String?
    let processID: Int?
    let engines: [EngineCapability]?
    let outputPath: String?
    let speakerPath: String?
    let shutdown: Bool?
    let cancelled: Bool?
}

enum WorkerJSONCodec {
    static func encode(_ command: WorkerCommand) throws -> Data {
        try JSONEncoder().encode(command)
    }

    static func decode(_ data: Data) throws -> WorkerMessage {
        let envelope = try JSONDecoder().decode(WorkerEnvelope.self, from: data)
        switch envelope.type {
        case "ready":
            return .ready(
                requestID: try required(envelope.requestID, "requestID"),
                engineID: try required(envelope.engineID, "engineID")
            )
        case "progress":
            return .progress(
                requestID: try required(envelope.requestID, "requestID"),
                progress: try required(envelope.progress, "progress"),
                stage: try required(envelope.stage, "stage")
            )
        case "error":
            return .error(
                WorkerFailure(
                    requestID: envelope.requestID,
                    code: try required(envelope.code, "code"),
                    message: try required(envelope.message, "message")
                )
            )
        case "result":
            return .result(
                WorkerResult(
                    requestID: try required(envelope.requestID, "requestID"),
                    status: envelope.status,
                    processID: envelope.processID,
                    engines: envelope.engines,
                    outputPath: envelope.outputPath,
                    speakerPath: envelope.speakerPath,
                    shutdown: envelope.shutdown,
                    cancelled: envelope.cancelled
                )
            )
        default:
            throw WorkerCodecError.unknownMessageType(envelope.type)
        }
    }

    private static func required<T>(_ value: T?, _ field: String) throws -> T {
        guard let value else { throw WorkerCodecError.missingField(field) }
        return value
    }
}

enum WorkerCodecError: Error, Equatable {
    case missingField(String)
    case unknownMessageType(String)
}

struct JSONLineBuffer: Sendable {
    private var bytes = Data()

    mutating func append(_ data: Data) -> [String] {
        bytes.append(data)
        var lines: [String] = []
        while let newline = bytes.firstIndex(of: 0x0A) {
            let lineData = bytes[..<newline]
            bytes.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

