import Foundation

enum EmotionPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case calm = "calm"
    case happy = "happy"
    case sad = "sad"
    case angry = "angry"
    case afraid = "afraid"
    case surprised = "surprised"
    case disgusted = "disgusted"
    case melancholic = "melancholic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: "平静"
        case .happy: "开心"
        case .sad: "悲伤"
        case .angry: "生气"
        case .afraid: "害怕"
        case .surprised: "惊讶"
        case .disgusted: "厌恶"
        case .melancholic: "忧郁"
        }
    }

    var symbol: String {
        switch self {
        case .calm: "water.waves"
        case .happy: "sun.max"
        case .sad: "cloud.rain"
        case .angry: "flame"
        case .afraid: "exclamationmark.triangle"
        case .surprised: "sparkles"
        case .disgusted: "hand.raised"
        case .melancholic: "moon.stars"
        }
    }
}

enum GenerationValidationError: LocalizedError, Equatable {
    case emptyText
    case missingVoice
    case unavailableVoice

    var errorDescription: String? {
        switch self {
        case .emptyText: "请输入需要合成的文字"
        case .missingVoice: "请先选择一个声音"
        case .unavailableVoice: "所选声音的文件不可用，请重新导入"
        }
    }
}

struct GenerationDraft: Sendable {
    var text: String
    var voice: VoiceProfile?
    var emotion: EmotionPreset = .calm
    var emotionStrength = 0.6
    var speed = 1.0
    var diffusionSteps = 25
    var emotionWeights: [String: Double] = [:]
    var temperature = 0.8
    var topP = 0.8
    var topK = 30
    var repetitionPenalty = 10.0
    var cfgRate = 0.7
    var seed: Int?
    var maxMelTokens = 1500
    var maxTextTokensPerSegment = 120
    var intervalSilenceMS = 200
    var segmentOverlapMS = 50

    func validated() throws -> GenerationDraft {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationValidationError.emptyText
        }
        guard let voice else { throw GenerationValidationError.missingVoice }
        guard voice.isAvailable else { throw GenerationValidationError.unavailableVoice }
        return self
    }

    static func showsEmotionControls(for capability: EngineCapability?) -> Bool {
        capability?.supportsEmotion == true
    }

    func workerPayload(
        outputURL: URL,
        capability: EngineCapability?
    ) throws -> [String: JSONValue] {
        let draft = try validated()
        guard let voice = draft.voice else { throw GenerationValidationError.missingVoice }
        var payload: [String: JSONValue] = [
            "text": .string(draft.text.trimmingCharacters(in: .whitespacesAndNewlines)),
            "speakerPath": .string(voice.speakerPath),
            "outputPath": .string(outputURL.path),
            "diffusionSteps": .number(Double(draft.diffusionSteps)),
            "temperature": .number(draft.temperature),
            "topP": .number(draft.topP),
            "topK": .number(Double(draft.topK)),
            "repetitionPenalty": .number(draft.repetitionPenalty),
            "cfgRate": .number(draft.cfgRate),
            "maxMelTokens": .number(Double(draft.maxMelTokens)),
            "maxTextTokensPerSegment": .number(Double(draft.maxTextTokensPerSegment)),
            "intervalSilenceMS": .number(Double(draft.intervalSilenceMS)),
            "segmentOverlapMS": .number(Double(draft.segmentOverlapMS)),
            "speed": .number(capability?.supportsSpeed == true ? draft.speed : 1.0),
        ]
        if capability?.supportsEmotion == true {
            let weights = draft.emotionWeights.isEmpty
                ? [draft.emotion.rawValue: 1.0]
                : draft.emotionWeights
            payload["emotion"] = .object(weights.mapValues(JSONValue.number))
            payload["emotionStrength"] = .number(draft.emotionStrength)
        }
        if let seed = draft.seed {
            payload["seed"] = .number(Double(seed))
        }
        return payload
    }

    static func outputFilename(text: String, date: Date = Date()) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
        let cleaned = text
            .components(separatedBy: illegal)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let readable = String(cleaned.prefix(18)).trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = readable.isEmpty ? "语音" : readable
        return "\(stem)-\(Self.timestamp.string(from: date)).wav"
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

struct SynthesisParameters: Codable, Equatable, Sendable {
    var emotion: EmotionPreset = .calm
    var emotionStrength = 0.6
    var emotionWeights: [String: Double] = [:]
    var speed = 1.0
    var diffusionSteps = 25
    var temperature = 0.8
    var topP = 0.8
    var topK = 30
    var repetitionPenalty = 10.0
    var cfgRate = 0.7
    var seed: Int?
    var maxMelTokens = 1500
    var maxTextTokensPerSegment = 120
    var intervalSilenceMS = 200
    var segmentOverlapMS = 50
}

struct GenerationPreset: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let voiceID: String
    let parameters: SynthesisParameters
    let createdAt: Date
}

struct GenerationResult: Equatable, Sendable {
    let outputURL: URL
    let duration: TimeInterval
    let generationSeconds: TimeInterval
}
