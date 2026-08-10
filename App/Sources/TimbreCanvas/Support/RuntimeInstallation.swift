import Foundation

private struct RuntimeConfiguration: Decodable {
    let schemaVersion: Int
    let pythonPath: String?
    let modelPath: String?
    let voiceRoot: String?
    let presetRoot: String?
    let cacheRoot: String?
}

struct RuntimeInstallation: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case unsupportedSchema(Int)
    }

    let supportRoot: URL
    let pythonURL: URL
    let modelURL: URL
    let workerModuleRoot: URL
    let voiceRoot: URL
    let presetRoot: URL
    let configURL: URL
    let cacheRoot: URL

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleResourceRoot: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    ) throws -> RuntimeInstallation {
        let supportRoot = supportRoot(environment: environment, homeDirectory: homeDirectory)

        let configURL = supportRoot.appending(path: "config.json")
        let configuration: RuntimeConfiguration?
        if FileManager.default.fileExists(atPath: configURL.path) {
            configuration = try JSONDecoder().decode(
                RuntimeConfiguration.self,
                from: Data(contentsOf: configURL)
            )
            guard configuration?.schemaVersion == 1 else {
                throw Error.unsupportedSchema(configuration?.schemaVersion ?? 0)
            }
        } else {
            configuration = nil
        }

        func configuredURL(_ path: String?, default defaultURL: URL) -> URL {
            guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                return defaultURL
            }
            return URL(fileURLWithPath: path)
        }

        return RuntimeInstallation(
            supportRoot: supportRoot,
            pythonURL: configuredURL(
                configuration?.pythonPath,
                default: supportRoot.appending(path: "Runtime/.venv/bin/python")
            ),
            modelURL: configuredURL(
                configuration?.modelPath,
                default: supportRoot.appending(path: "Models/IndexTTS-2-MLX-8bit")
            ),
            workerModuleRoot: bundleResourceRoot.appending(path: "RuntimeHost"),
            voiceRoot: configuredURL(
                configuration?.voiceRoot,
                default: supportRoot.appending(path: "Voices")
            ),
            presetRoot: configuredURL(
                configuration?.presetRoot,
                default: supportRoot.appending(path: "Presets")
            ),
            configURL: configURL,
            cacheRoot: configuredURL(
                configuration?.cacheRoot,
                default: supportRoot.appending(path: "Cache")
            )
        )
    }

    static func defaults(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleResourceRoot: URL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    ) -> RuntimeInstallation {
        let supportRoot = supportRoot(environment: environment, homeDirectory: homeDirectory)
        return RuntimeInstallation(
            supportRoot: supportRoot,
            pythonURL: supportRoot.appending(path: "Runtime/.venv/bin/python"),
            modelURL: supportRoot.appending(path: "Models/IndexTTS-2-MLX-8bit"),
            workerModuleRoot: bundleResourceRoot.appending(path: "RuntimeHost"),
            voiceRoot: supportRoot.appending(path: "Voices"),
            presetRoot: supportRoot.appending(path: "Presets"),
            configURL: supportRoot.appending(path: "config.json"),
            cacheRoot: supportRoot.appending(path: "Cache")
        )
    }

    private static func supportRoot(
        environment: [String: String],
        homeDirectory: URL
    ) -> URL {
        if let override = environment["TIMBRECANVAS_RUNTIME_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return homeDirectory.appending(
            path: "Library/Application Support/TimbreCanvas",
            directoryHint: .isDirectory
        )
    }
}
