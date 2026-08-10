import Combine
import Foundation

enum VoiceLibraryError: LocalizedError, Equatable {
    case profileNotFound
    case builtInDeletionDenied
    case emptyName

    var errorDescription: String? {
        switch self {
        case .profileNotFound: "找不到这个音色"
        case .builtInDeletionDenied: "默认音色不能删除"
        case .emptyName: "音色名称不能为空"
        }
    }
}

private struct VoiceManifest: Codable {
    let schemaVersion: Int
    let profiles: [VoiceProfile]
}

@MainActor
final class VoiceLibraryStore: ObservableObject {
    @Published private(set) var profiles: [VoiceProfile]
    @Published var selectedID: String?
    @Published var searchText = ""

    let manifestURL: URL?
    let customDirectory: URL?

    init(
        profiles: [VoiceProfile],
        manifestURL: URL? = nil,
        customDirectory: URL? = nil
    ) {
        self.profiles = profiles
        self.manifestURL = manifestURL
        self.customDirectory = customDirectory
        selectedID = profiles.first?.id
    }

    static func live(installation: RuntimeInstallation) -> VoiceLibraryStore {
        let voices = installation.voiceRoot
        let manifest = voices.appending(path: "voices.json")
        let custom = voices.appending(path: "custom", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let restored = (try? loadManifest(at: manifest)) ?? []
        let customProfiles = restored.filter { $0.kind == .custom }
        let aliases = Dictionary(
            uniqueKeysWithValues: restored.filter { $0.kind == .builtIn }.map { ($0.id, $0.name) }
        )
        let builtIns = builtInProfiles(voiceRoot: voices).map { profile in
            var profile = profile
            profile.name = aliases[profile.id] ?? profile.name
            return profile
        }
        let store = VoiceLibraryStore(
            profiles: builtIns + customProfiles,
            manifestURL: manifest,
            customDirectory: custom
        )
        try? store.persist()
        return store
    }

    var builtInProfiles: [VoiceProfile] { profiles.filter { $0.kind == .builtIn } }
    var customProfiles: [VoiceProfile] { profiles.filter { $0.kind == .custom } }
    var filteredBuiltIns: [VoiceProfile] { filtered(builtInProfiles) }
    var filteredCustom: [VoiceProfile] { filtered(customProfiles) }
    var selectedVoice: VoiceProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }

    func add(_ profile: VoiceProfile) throws {
        profiles.append(profile)
        selectedID = profile.id
        try persist()
    }

    func rename(id: String, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceLibraryError.emptyName }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw VoiceLibraryError.profileNotFound
        }
        profiles[index].name = trimmed
        try persist()
    }

    func delete(id: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw VoiceLibraryError.profileNotFound
        }
        let profile = profiles[index]
        guard profile.kind == .custom else { throw VoiceLibraryError.builtInDeletionDenied }
        removeOwnedFile(profile.referenceURL)
        removeOwnedFile(profile.speakerURL)
        profiles.remove(at: index)
        selectedID = profiles.first?.id
        try persist()
    }

    static func loadManifest(at url: URL) throws -> [VoiceProfile] {
        let manifest = try JSONDecoder().decode(VoiceManifest.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return manifest.profiles
    }

    private func filtered(_ source: [VoiceProfile]) -> [VoiceProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.note.localizedCaseInsensitiveContains(query)
        }
    }

    private func persist() throws {
        guard let manifestURL else { return }
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(VoiceManifest(schemaVersion: 1, profiles: profiles))
        try data.write(to: manifestURL, options: .atomic)
    }

    private func removeOwnedFile(_ url: URL) {
        guard let customDirectory else { return }
        let root = customDirectory.standardizedFileURL.path + "/"
        let candidate = url.standardizedFileURL.path
        guard candidate.hasPrefix(root) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func builtInProfiles(voiceRoot: URL) -> [VoiceProfile] {
        let voiceDirectory = voiceRoot.appending(path: "builtin")
        let identifiers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12]
        return identifiers.map { number in
            let suffix = String(format: "%02d", number)
            let voiceID = "voice_\(suffix)"
            return VoiceProfile(
                id: "builtin-\(voiceID)",
                engineID: "indextts2",
                profileVersion: 1,
                name: "官方示例 \(suffix)",
                kind: .builtIn,
                referencePath: voiceDirectory.appending(path: "\(voiceID).wav").path,
                speakerPath: voiceDirectory.appending(path: "\(voiceID).npz").path,
                createdAt: "2026-08-10T00:00:00Z",
                note: "IndexTTS 2 官方示例"
            )
        }
    }
}
