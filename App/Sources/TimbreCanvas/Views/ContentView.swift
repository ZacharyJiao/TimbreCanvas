import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var voiceLibrary: VoiceLibraryStore
    @StateObject private var generation = GenerationStore()
    @StateObject private var playback = PlaybackService()
    @State private var importErrorMessage: String?

    var body: some View {
        ZStack {
            PaperBackground()
            NavigationSplitView {
                VoiceSidebarView(store: voiceLibrary, importAction: importVoice)
            } detail: {
                ComposerView(generation: generation, playback: playback)
                    .padding(24)
                    .navigationTitle("语音创作")
            }
            .background(.clear)
        }
        .task { appModel.startIfNeeded() }
        .onDisappear { appModel.shutdown() }
        .alert(
            "无法导入音色",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "未知错误")
        }
    }

    private func importVoice() {
        let service = AudioImportService()
        guard let source = service.chooseReferenceAudio() else { return }
        guard let customDirectory = voiceLibrary.customDirectory else { return }
        let id = UUID().uuidString.lowercased()
        let reference = customDirectory.appending(path: "\(id).wav")
        let speaker = customDirectory.appending(path: "\(id).npz")
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try service.convertToMonoWAV(source: source, destination: reference)
                }.value
                _ = try await appModel.extractVoice(referenceURL: reference, speakerURL: speaker)
                try voiceLibrary.add(
                    VoiceProfile(
                        id: id,
                        engineID: "indextts2",
                        profileVersion: 1,
                        name: source.deletingPathExtension().lastPathComponent,
                        kind: .custom,
                        referencePath: reference.path,
                        speakerPath: speaker.path,
                        createdAt: Date().ISO8601Format(),
                        note: ""
                    )
                )
            } catch {
                try? FileManager.default.removeItem(at: reference)
                try? FileManager.default.removeItem(at: speaker)
                importErrorMessage = error.localizedDescription
            }
        }
    }
}
