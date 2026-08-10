import Foundation
import Testing
@testable import TimbreCanvas

private func voice(
    id: String,
    name: String,
    kind: VoiceKind,
    engineID: String = "indextts2"
) -> VoiceProfile {
    VoiceProfile(
        id: id,
        engineID: engineID,
        profileVersion: 1,
        name: name,
        kind: kind,
        referencePath: "/tmp/\(id).wav",
        speakerPath: "/tmp/\(id).npz",
        createdAt: "2026-08-10T00:00:00Z",
        note: ""
    )
}

@Test func voiceProfileDecodesEngineAndProfileVersion() throws {
    let data = Data(
        #"{"id":"v1","engineID":"indextts2","profileVersion":1,"name":"测试","kind":"custom","referencePath":"/tmp/a.wav","speakerPath":"/tmp/a.npz","createdAt":"2026-08-10T00:00:00Z","note":""}"#.utf8
    )

    let profile = try JSONDecoder().decode(VoiceProfile.self, from: data)

    #expect(profile.engineID == "indextts2")
    #expect(profile.profileVersion == 1)
    #expect(profile.kind == .custom)
}

@Test @MainActor func voiceLibraryGroupsAndSearchesProfiles() {
    let store = VoiceLibraryStore(
        profiles: [
            voice(id: "b1", name: "官方示例 01", kind: .builtIn),
            voice(id: "c1", name: "我的旁白", kind: .custom),
        ]
    )

    #expect(store.builtInProfiles.map(\.id) == ["b1"])
    #expect(store.customProfiles.map(\.id) == ["c1"])

    store.searchText = "旁白"
    #expect(store.filteredBuiltIns.isEmpty)
    #expect(store.filteredCustom.map(\.id) == ["c1"])
}

@Test @MainActor func builtInVoiceCannotBeDeleted() {
    let store = VoiceLibraryStore(
        profiles: [voice(id: "b1", name: "官方示例 01", kind: .builtIn)]
    )

    #expect(throws: VoiceLibraryError.builtInDeletionDenied) {
        try store.delete(id: "b1")
    }
}

@Test @MainActor func customRenamePersistsManifest() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appending(path: ".build/voice-library-test", directoryHint: .isDirectory)
    let manifest = directory.appending(path: "voices.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = VoiceLibraryStore(
        profiles: [voice(id: "c1", name: "旧名称", kind: .custom)],
        manifestURL: manifest,
        customDirectory: directory
    )

    try store.rename(id: "c1", to: "新名称")
    let restored = try VoiceLibraryStore.loadManifest(at: manifest)

    #expect(restored.map(\.name) == ["新名称"])
}

@Test @MainActor func corruptVoiceManifestIsNeverOverwrittenAtLaunch() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-corrupt-voice-manifest-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }
    let voices = root.appending(path: "Voices", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: voices, withIntermediateDirectories: true)
    let manifest = voices.appending(path: "voices.json")
    let original = Data("{not valid json\n".utf8)
    try original.write(to: manifest)
    let installation = RuntimeInstallation.defaults(
        environment: ["TIMBRECANVAS_RUNTIME_ROOT": root.path],
        homeDirectory: fileManager.temporaryDirectory,
        bundleResourceRoot: root.appending(path: "Resources")
    )

    let store = VoiceLibraryStore.live(installation: installation)

    #expect(try Data(contentsOf: manifest) == original)
    #expect(store.persistenceErrorMessage?.contains("voices.json") == true)
    var rejectedMutation = false
    do {
        try store.rename(id: "builtin-voice_01", to: "不会覆盖损坏清单")
    } catch {
        rejectedMutation = true
    }
    #expect(rejectedMutation)
}

@Test @MainActor func duplicateVoiceIdentifiersAreRejectedBeforeDictionaryConstruction() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "timbrecanvas-duplicate-voice-manifest-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manifest = root.appending(path: "voices.json")
    let duplicate = voice(id: "builtin-voice_01", name: "Synthetic", kind: .builtIn)
    let data = try JSONEncoder().encode([
        "schemaVersion": JSONValue.number(1),
        "profiles": JSONValue.array(
            try [duplicate, duplicate].map {
                try JSONDecoder().decode(
                    JSONValue.self,
                    from: JSONEncoder().encode($0)
                )
            }
        ),
    ])
    try data.write(to: manifest)

    #expect(throws: (any Error).self) {
        try VoiceLibraryStore.loadManifest(at: manifest)
    }
}

@Test @MainActor func customVoiceDeletionRejectsIntermediateSymlinkEscape() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-voice-symlink-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }
    let custom = root.appending(path: "custom", directoryHint: .isDirectory)
    let outside = root.appending(path: "outside", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
    let externalReference = outside.appending(path: "fixture.wav")
    let externalSpeaker = outside.appending(path: "fixture.npz")
    try Data("external reference".utf8).write(to: externalReference)
    try Data("external speaker".utf8).write(to: externalSpeaker)
    try fileManager.createSymbolicLink(
        at: custom.appending(path: "link"),
        withDestinationURL: outside
    )
    var profile = voice(id: "custom-symlink", name: "Synthetic", kind: .custom)
    profile = VoiceProfile(
        id: profile.id,
        engineID: profile.engineID,
        profileVersion: profile.profileVersion,
        name: profile.name,
        kind: profile.kind,
        referencePath: custom.appending(path: "link/fixture.wav").path,
        speakerPath: custom.appending(path: "link/fixture.npz").path,
        createdAt: profile.createdAt,
        note: profile.note
    )
    let store = VoiceLibraryStore(
        profiles: [profile],
        manifestURL: root.appending(path: "voices.json"),
        customDirectory: custom
    )

    #expect(throws: VoiceLibraryError.unsafeProfilePath) {
        try store.delete(id: profile.id)
    }
    #expect(fileManager.fileExists(atPath: externalReference.path))
    #expect(fileManager.fileExists(atPath: externalSpeaker.path))
}

@Test @MainActor func customVoiceCannotOccupyTheBuiltInIdentifierNamespace() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "timbrecanvas-reserved-voice-id-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let manifest = root.appending(path: "voices.json")
    let reserved = voice(id: "builtin-voice_01", name: "Synthetic", kind: .custom)
    let data = try JSONEncoder().encode([
        "schemaVersion": JSONValue.number(1),
        "profiles": JSONValue.array([
            try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(reserved))
        ]),
    ])
    try data.write(to: manifest)

    #expect(throws: (any Error).self) {
        try VoiceLibraryStore.loadManifest(at: manifest)
    }
}

@Test @MainActor func failedManifestWriteRollsBackMutationsAndPreservesVoiceFiles() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
        path: "timbrecanvas-voice-write-failure-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }
    let custom = root.appending(path: "custom", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: custom, withIntermediateDirectories: true)
    let reference = custom.appending(path: "fixture.wav")
    let speaker = custom.appending(path: "fixture.npz")
    try Data("reference".utf8).write(to: reference)
    try Data("speaker".utf8).write(to: speaker)
    let profile = VoiceProfile(
        id: "custom-fixture",
        engineID: "indextts2",
        profileVersion: 1,
        name: "Original",
        kind: .custom,
        referencePath: reference.path,
        speakerPath: speaker.path,
        createdAt: "2026-01-01T00:00:00Z",
        note: ""
    )
    let store = VoiceLibraryStore(
        profiles: [profile],
        manifestURL: root.appending(path: "voices.json"),
        customDirectory: custom,
        manifestWriter: { _, _ in throw CocoaError(.fileWriteUnknown) }
    )

    #expect(throws: (any Error).self) { try store.rename(id: profile.id, to: "Changed") }
    #expect(store.profiles.first?.name == "Original")
    #expect(throws: (any Error).self) {
        try store.add(voice(id: "custom-new", name: "New", kind: .custom))
    }
    #expect(store.profiles.map { $0.id } == [profile.id])
    #expect(throws: (any Error).self) { try store.delete(id: profile.id) }
    #expect(store.profiles.map { $0.id } == [profile.id])
    #expect(fileManager.fileExists(atPath: reference.path))
    #expect(fileManager.fileExists(atPath: speaker.path))
}
