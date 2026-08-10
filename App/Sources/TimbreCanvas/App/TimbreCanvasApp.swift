import AppKit
import SwiftUI

@main
struct TimbreCanvasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @StateObject private var voiceLibrary = VoiceLibraryStore.live(
        projectRoot: RuntimePaths.projectRoot()
    )
    @StateObject private var presets = GenerationPresetStore.live(
        projectRoot: RuntimePaths.projectRoot()
    )

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
