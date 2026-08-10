import Foundation
import Testing
@testable import TimbreCanvas

@Test func generationDraftRejectsEmptyTextAndMissingVoice() {
    #expect(throws: GenerationValidationError.emptyText) {
        try GenerationDraft(text: "   ", voice: nil).validated()
    }

    #expect(throws: GenerationValidationError.missingVoice) {
        try GenerationDraft(text: "你好", voice: nil).validated()
    }
}

@Test func emotionControlsHideWhenCapabilityIsAbsent() {
    let incapable = EngineCapability(
        engineID: "simple",
        displayName: "Simple",
        supportsEmotion: false,
        supportsSpeed: false,
        speakerProfileVersion: 1
    )
    let capable = EngineCapability(
        engineID: "indextts2",
        displayName: "IndexTTS 2",
        supportsEmotion: true,
        supportsSpeed: true,
        speakerProfileVersion: 1
    )

    #expect(!GenerationDraft.showsEmotionControls(for: incapable))
    #expect(GenerationDraft.showsEmotionControls(for: capable))
}

@Test @MainActor func outputDirectoryPersistsAcrossStores() throws {
    let suiteName = "TimbreCanvas.GenerationStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let folder = URL(fileURLWithPath: "/tmp/IndexTTS Exports", isDirectory: true)
    let first = GenerationStore(defaults: defaults)

    first.outputDirectory = folder
    let restored = GenerationStore(defaults: defaults)

    #expect(restored.outputDirectory == folder)
}

@Test func generatedFilenameIsSafeAndReadable() {
    let date = Date(timeIntervalSince1970: 1_786_291_200)

    let name = GenerationDraft.outputFilename(text: "../你好，世界？", date: date)

    #expect(!name.contains("/"))
    #expect(name.hasPrefix("你好，世界"))
    #expect(name.hasSuffix(".wav"))
}

@Test @MainActor func completedGenerationStoresPlaybackMetadata() {
    let store = GenerationStore(defaults: UserDefaults.standard)
    let result = GenerationResult(
        outputURL: URL(fileURLWithPath: "/tmp/result.wav"),
        duration: 3.2,
        generationSeconds: 4.5
    )

    store.complete(with: result)

    #expect(store.result == result)
    #expect(!store.isGenerating)
}

@Test func generationPayloadIncludesAdvancedIndexTTS2Parameters() throws {
    let directory = URL(fileURLWithPath: "/tmp/indextts-payload-test", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let reference = directory.appending(path: "voice.wav")
    let speaker = directory.appending(path: "voice.npz")
    FileManager.default.createFile(atPath: reference.path, contents: Data())
    FileManager.default.createFile(atPath: speaker.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: directory) }
    var draft = GenerationDraft(
        text: "测试",
        voice: VoiceProfile(
            id: "voice",
            engineID: "indextts2",
            profileVersion: 1,
            name: "测试音色",
            kind: .custom,
            referencePath: reference.path,
            speakerPath: speaker.path,
            createdAt: "2026-08-10T00:00:00Z",
            note: ""
        )
    )
    draft.emotionWeights = ["happy": 0.7, "calm": 0.3]
    draft.temperature = 0.65
    draft.topP = 0.9
    draft.topK = 42
    draft.repetitionPenalty = 8.5
    draft.cfgRate = 0.8
    draft.seed = 2026
    draft.intervalSilenceMS = 320
    draft.segmentOverlapMS = 80
    let capability = EngineCapability(
        engineID: "indextts2",
        displayName: "IndexTTS 2",
        supportsEmotion: true,
        supportsSpeed: true,
        speakerProfileVersion: 1
    )

    let payload = try draft.workerPayload(
        outputURL: directory.appending(path: "result.wav"),
        capability: capability
    )

    #expect(payload["temperature"] == .number(0.65))
    #expect(payload["topP"] == .number(0.9))
    #expect(payload["topK"] == .number(42))
    #expect(payload["repetitionPenalty"] == .number(8.5))
    #expect(payload["cfgRate"] == .number(0.8))
    #expect(payload["seed"] == .number(2026))
    #expect(payload["intervalSilenceMS"] == .number(320))
    #expect(payload["segmentOverlapMS"] == .number(80))
    #expect(payload["emotion"] == .object(["happy": .number(0.7), "calm": .number(0.3)]))
}
