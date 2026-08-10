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

