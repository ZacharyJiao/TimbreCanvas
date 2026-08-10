import Combine
import Foundation

enum VoiceLibraryError: LocalizedError, Equatable {
    case profileNotFound
    case builtInDeletionDenied
    case emptyName
    case manifestUnavailable
    case unsafeProfilePath

    var errorDescription: String? {
        switch self {
        case .profileNotFound: "找不到这个音色"
        case .builtInDeletionDenied: "默认音色不能删除"
        case .emptyName: "音色名称不能为空"
        case .manifestUnavailable: "音色清单已损坏；请先恢复 voices.json，原文件不会被覆盖"
        case .unsafeProfilePath: "音色文件路径不安全，未执行删除"
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
    private let persistenceError: VoiceLibraryError?
    private let manifestWriter: (Data, URL) throws -> Void

    init(
        profiles: [VoiceProfile],
        manifestURL: URL? = nil,
        customDirectory: URL? = nil,
        persistenceError: VoiceLibraryError? = nil,
        manifestWriter: ((Data, URL) throws -> Void)? = nil
    ) {
        self.profiles = profiles
        self.manifestURL = manifestURL
        self.customDirectory = customDirectory
        self.persistenceError = persistenceError
        self.manifestWriter = manifestWriter ?? { data, url in
            try data.write(to: url, options: .atomic)
        }
        selectedID = profiles.first?.id
    }

    static func live(installation: RuntimeInstallation) -> VoiceLibraryStore {
        let voices = installation.voiceRoot
        let manifest = voices.appending(path: "voices.json")
        let custom = voices.appending(path: "custom", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let restored: [VoiceProfile]
        let persistenceError: VoiceLibraryError?
        if FileManager.default.fileExists(atPath: manifest.path) {
            do {
                restored = try loadManifest(at: manifest)
                persistenceError = nil
            } catch {
                restored = []
                persistenceError = .manifestUnavailable
            }
        } else {
            restored = []
            persistenceError = nil
        }
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
            customDirectory: custom,
            persistenceError: persistenceError
        )
        if persistenceError == nil {
            try? store.persist()
        }
        return store
    }

    var builtInProfiles: [VoiceProfile] { profiles.filter { $0.kind == .builtIn } }
    var customProfiles: [VoiceProfile] { profiles.filter { $0.kind == .custom } }
    var filteredBuiltIns: [VoiceProfile] { filtered(builtInProfiles) }
    var filteredCustom: [VoiceProfile] { filtered(customProfiles) }
    var selectedVoice: VoiceProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }
    var persistenceErrorMessage: String? { persistenceError?.errorDescription }

    func add(_ profile: VoiceProfile) throws {
        try ensurePersistenceAvailable()
        let previousProfiles = profiles
        let previousSelection = selectedID
        profiles.append(profile)
        selectedID = profile.id
        do {
            try persist()
        } catch {
            profiles = previousProfiles
            selectedID = previousSelection
            throw error
        }
    }

    func rename(id: String, to newName: String) throws {
        try ensurePersistenceAvailable()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VoiceLibraryError.emptyName }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw VoiceLibraryError.profileNotFound
        }
        let previousName = profiles[index].name
        profiles[index].name = trimmed
        do {
            try persist()
        } catch {
            profiles[index].name = previousName
            throw error
        }
    }

    func delete(id: String) throws {
        try ensurePersistenceAvailable()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw VoiceLibraryError.profileNotFound
        }
        let profile = profiles[index]
        guard profile.kind == .custom else { throw VoiceLibraryError.builtInDeletionDenied }
        let reference = try ownedFile(profile.referenceURL, expectedExtension: "wav")
        let speaker = try ownedFile(profile.speakerURL, expectedExtension: "npz")
        let previousProfiles = profiles
        let previousSelection = selectedID
        profiles.remove(at: index)
        selectedID = profiles.first?.id
        do {
            try persist()
        } catch {
            profiles = previousProfiles
            selectedID = previousSelection
            throw error
        }
        try? FileManager.default.removeItem(at: reference)
        try? FileManager.default.removeItem(at: speaker)
    }

    static func loadManifest(at url: URL) throws -> [VoiceProfile] {
        let manifest = try JSONDecoder().decode(VoiceManifest.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        try validateProfiles(manifest.profiles)
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
        try ensurePersistenceAvailable()
        guard let manifestURL else { return }
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try Self.validateProfiles(profiles)
        let data = try encoder.encode(VoiceManifest(schemaVersion: 1, profiles: profiles))
        try manifestWriter(data, manifestURL)
    }

    private func ensurePersistenceAvailable() throws {
        if let persistenceError {
            throw persistenceError
        }
    }

    private func ownedFile(_ url: URL, expectedExtension: String) throws -> URL {
        guard let customDirectory else { throw VoiceLibraryError.unsafeProfilePath }
        let root = customDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL
        let resolvedParent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        guard resolvedParent == root,
              candidate.pathExtension.caseInsensitiveCompare(expectedExtension) == .orderedSame,
              !candidate.lastPathComponent.hasPrefix(".") else {
            throw VoiceLibraryError.unsafeProfilePath
        }
        return candidate
    }

    private static func validateProfiles(_ profiles: [VoiceProfile]) throws {
        let identifiers = profiles.map(\.id)
        guard Set(identifiers).count == identifiers.count,
              profiles.allSatisfy({ profile in
                  !profile.id.isEmpty
                      && !profile.engineID.isEmpty
                      && profile.profileVersion > 0
                      && !profile.name.isEmpty
                      && !profile.referencePath.isEmpty
                      && !profile.speakerPath.isEmpty
                      && !profile.createdAt.isEmpty
                      && !(profile.kind == .custom && profile.id.hasPrefix("builtin-"))
              }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
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
