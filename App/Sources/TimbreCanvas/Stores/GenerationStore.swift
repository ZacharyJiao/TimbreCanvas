import AVFoundation
import Combine
import Foundation

@MainActor
final class GenerationStore: ObservableObject {
    private static let outputDirectoryKey = "generation.outputDirectory"

    @Published var text = ""
    @Published var emotion: EmotionPreset = .calm
    @Published var emotionStrength = 0.6
    @Published var speed = 1.0
    @Published var diffusionSteps = 25
    @Published var emotionWeights: [String: Double] = [:]
    @Published var temperature = 0.8
    @Published var topP = 0.8
    @Published var topK = 30
    @Published var repetitionPenalty = 10.0
    @Published var cfgRate = 0.7
    @Published var seed: Int?
    @Published var maxMelTokens = 1500
    @Published var maxTextTokensPerSegment = 120
    @Published var intervalSilenceMS = 200
    @Published var segmentOverlapMS = 50
    @Published private(set) var result: GenerationResult?
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published var outputDirectory: URL {
        didSet { defaults.set(outputDirectory.path, forKey: Self.outputDirectoryKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: Self.outputDirectoryKey), !saved.isEmpty {
            outputDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            outputDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Music/TimbreCanvas", directoryHint: .isDirectory)
        }
    }

    func generate(voice: VoiceProfile?, capability: EngineCapability?, appModel: AppModel) async {
        let draft = GenerationDraft(
            text: text,
            voice: voice,
            emotion: emotion,
            emotionStrength: emotionStrength,
            speed: speed,
            diffusionSteps: diffusionSteps,
            emotionWeights: emotionWeights,
            temperature: temperature,
            topP: topP,
            topK: topK,
            repetitionPenalty: repetitionPenalty,
            cfgRate: cfgRate,
            seed: seed,
            maxMelTokens: maxMelTokens,
            maxTextTokensPerSegment: maxTextTokensPerSegment,
            intervalSilenceMS: intervalSilenceMS,
            segmentOverlapMS: segmentOverlapMS
        )

        do {
            let validated = try draft.validated()
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let requestedOutput = outputDirectory.appending(
                path: GenerationDraft.outputFilename(text: validated.text)
            )
            isGenerating = true
            errorMessage = nil
            result = nil
            let started = ContinuousClock.now
            let outputURL = try await appModel.generate(
                draft: validated,
                outputURL: requestedOutput,
                capability: capability
            )
            let elapsed = started.duration(to: .now)
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            complete(
                with: GenerationResult(
                    outputURL: outputURL,
                    duration: Self.audioDuration(at: outputURL),
                    generationSeconds: seconds
                )
            )
        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
        }
    }

    func complete(with result: GenerationResult) {
        self.result = result
        isGenerating = false
        errorMessage = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    var synthesisParameters: SynthesisParameters {
        SynthesisParameters(
            emotion: emotion,
            emotionStrength: emotionStrength,
            emotionWeights: emotionWeights,
            speed: speed,
            diffusionSteps: diffusionSteps,
            temperature: temperature,
            topP: topP,
            topK: topK,
            repetitionPenalty: repetitionPenalty,
            cfgRate: cfgRate,
            seed: seed,
            maxMelTokens: maxMelTokens,
            maxTextTokensPerSegment: maxTextTokensPerSegment,
            intervalSilenceMS: intervalSilenceMS,
            segmentOverlapMS: segmentOverlapMS
        )
    }

    func apply(_ parameters: SynthesisParameters) {
        emotion = parameters.emotion
        emotionStrength = parameters.emotionStrength
        emotionWeights = parameters.emotionWeights
        speed = parameters.speed
        diffusionSteps = parameters.diffusionSteps
        temperature = parameters.temperature
        topP = parameters.topP
        topK = parameters.topK
        repetitionPenalty = parameters.repetitionPenalty
        cfgRate = parameters.cfgRate
        seed = parameters.seed
        maxMelTokens = parameters.maxMelTokens
        maxTextTokensPerSegment = parameters.maxTextTokensPerSegment
        intervalSilenceMS = parameters.intervalSilenceMS
        segmentOverlapMS = parameters.segmentOverlapMS
    }

    private static func audioDuration(at url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else {
            return 0
        }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
