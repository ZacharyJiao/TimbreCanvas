import Combine
import Foundation

enum GenerationPresetError: LocalizedError, Equatable {
    case emptyName
    case presetNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "预设名称不能为空"
        case .presetNotFound: "找不到这个预设"
        }
    }
}

private struct GenerationPresetManifest: Codable {
    let schemaVersion: Int
    let presets: [GenerationPreset]
}

@MainActor
final class GenerationPresetStore: ObservableObject {
    @Published private(set) var presets: [GenerationPreset]
    @Published var selectedID: UUID?

    let manifestURL: URL

    init(manifestURL: URL) {
        self.manifestURL = manifestURL
        presets = (try? Self.load(at: manifestURL)) ?? []
    }

    static func live(projectRoot: URL) -> GenerationPresetStore {
        GenerationPresetStore(
            manifestURL: projectRoot.appending(path: "runtime/presets/presets.json")
        )
    }

    @discardableResult
    func save(
        name: String,
        voiceID: String,
        parameters: SynthesisParameters
    ) throws -> GenerationPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GenerationPresetError.emptyName }
        let preset = GenerationPreset(
            id: UUID(),
            name: trimmed,
            voiceID: voiceID,
            parameters: parameters,
            createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        )
        presets.append(preset)
        selectedID = preset.id
        try persist()
        return preset
    }

    func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GenerationPresetError.emptyName }
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            throw GenerationPresetError.presetNotFound
        }
        presets[index].name = trimmed
        try persist()
    }

    func delete(id: UUID) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            throw GenerationPresetError.presetNotFound
        }
        presets.remove(at: index)
        if selectedID == id { selectedID = nil }
        try persist()
    }

    private static func load(at url: URL) throws -> [GenerationPreset] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            GenerationPresetManifest.self,
            from: Data(contentsOf: url)
        )
        guard manifest.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return manifest.presets
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            GenerationPresetManifest(schemaVersion: 1, presets: presets)
        ).write(to: manifestURL, options: .atomic)
    }
}
