import Foundation

enum VoiceKind: String, Codable, Hashable, Sendable {
    case builtIn
    case custom
}

struct VoiceProfile: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let engineID: String
    let profileVersion: Int
    var name: String
    let kind: VoiceKind
    let referencePath: String
    let speakerPath: String
    let createdAt: String
    var note: String

    var referenceURL: URL { URL(fileURLWithPath: referencePath) }
    var speakerURL: URL { URL(fileURLWithPath: speakerPath) }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: referencePath)
            && FileManager.default.fileExists(atPath: speakerPath)
    }
}

