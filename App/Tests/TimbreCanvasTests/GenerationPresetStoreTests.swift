import Foundation
import Testing
@testable import TimbreCanvas

@Test @MainActor func generationPresetPersistsVoiceAndAllParameters() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "TimbreCanvas.Presets.\(UUID().uuidString)")
    let manifest = directory.appending(path: "presets.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    var parameters = SynthesisParameters()
    parameters.emotion = .happy
    parameters.emotionWeights = ["happy": 0.7, "calm": 0.3]
    parameters.speed = 0.95
    parameters.seed = 42
    parameters.cfgRate = 0.82
    let first = GenerationPresetStore(manifestURL: manifest)

    let saved = try first.save(
        name: "温柔讲述",
        voiceID: "custom-narrator",
        parameters: parameters
    )
    let restored = GenerationPresetStore(manifestURL: manifest)

    #expect(restored.presets == [saved])
    #expect(restored.presets.first?.voiceID == "custom-narrator")
    #expect(restored.presets.first?.parameters == parameters)
}

@Test @MainActor func emptyPresetNameIsRejected() throws {
    let manifest = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "TimbreCanvas.Presets.\(UUID().uuidString)/presets.json")
    let store = GenerationPresetStore(manifestURL: manifest)

    #expect(throws: GenerationPresetError.emptyName) {
        try store.save(name: "   ", voiceID: "voice", parameters: SynthesisParameters())
    }
}
