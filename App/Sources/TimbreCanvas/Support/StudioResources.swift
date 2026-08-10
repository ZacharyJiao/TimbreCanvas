import Foundation

extension Bundle {
    static let studioResources: Bundle = {
        let bundleName = "TimbreCanvas_TimbreCanvas.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appending(path: bundleName),
            Bundle.main.bundleURL.appending(path: bundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appending(path: bundleName),
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        fatalError("找不到 TimbreCanvas 界面资源包")
    }()
}
