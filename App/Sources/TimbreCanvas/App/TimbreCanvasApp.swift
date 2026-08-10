import AppKit
import SwiftUI

@main
struct TimbreCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel
    @StateObject private var voiceLibrary: VoiceLibraryStore
    @StateObject private var presets: GenerationPresetStore

    init() {
        let installation = (try? RuntimeInstallation.resolve()) ?? .defaults()
        _appModel = StateObject(wrappedValue: AppModel(installation: installation))
        _voiceLibrary = StateObject(
            wrappedValue: VoiceLibraryStore.live(installation: installation)
        )
        _presets = StateObject(
            wrappedValue: GenerationPresetStore.live(installation: installation)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(voiceLibrary)
                .environmentObject(presets)
                .frame(minWidth: 880, minHeight: 600)
        }
        .defaultSize(width: 1_120, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
