import Foundation

enum RuntimePaths {
    static func projectRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        configuredBundlePath: String? = Bundle.main.object(
            forInfoDictionaryKey: "IndexTTSProjectRoot"
        ) as? String
    ) -> URL {
        if let configured = environment["INDEXTTS_PROJECT_ROOT"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        }

        if let configuredBundlePath, !configuredBundlePath.isEmpty,
           FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: configuredBundlePath).appending(path: "pyproject.toml").path
           ) {
            return URL(fileURLWithPath: configuredBundlePath, isDirectory: true).standardizedFileURL
        }

        if let executableURL {
            var candidate = executableURL
            for _ in 0..<5 { candidate.deleteLastPathComponent() }
            if FileManager.default.fileExists(atPath: candidate.appending(path: "pyproject.toml").path) {
                return candidate.standardizedFileURL
            }
        }

        if FileManager.default.fileExists(atPath: currentDirectory.appending(path: "pyproject.toml").path) {
            return currentDirectory.standardizedFileURL
        }

        return currentDirectory.standardizedFileURL
    }
}
