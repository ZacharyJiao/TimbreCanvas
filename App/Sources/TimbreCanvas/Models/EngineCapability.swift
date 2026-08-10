struct EngineCapability: Codable, Equatable, Sendable, Identifiable {
    let engineID: String
    let displayName: String
    let supportsEmotion: Bool
    let supportsSpeed: Bool
    let speakerProfileVersion: Int

    var id: String { engineID }
}

