import SwiftUI

struct PresetBarView: View {
    @EnvironmentObject private var voiceLibrary: VoiceLibraryStore
    @ObservedObject var store: GenerationPresetStore
    @ObservedObject var generation: GenerationStore

    @State private var saveName = ""
    @State private var showsSaveDialog = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                if store.presets.isEmpty {
                    Text("还没有保存的预设")
                } else {
                    ForEach(store.presets) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            if store.selectedID == preset.id {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                }
                if let selectedID = store.selectedID {
                    Divider()
                    Button("删除当前预设", role: .destructive) {
                        do { try store.delete(id: selectedID) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("预设：\(selectedName)")
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 18)

            Button("存为预设") {
                saveName = suggestedName
                showsSaveDialog = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(StudioDesign.accent)
            .disabled(voiceLibrary.selectedVoice == nil)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .studioSurface()
        .alert("保存生成预设", isPresented: $showsSaveDialog) {
            TextField("预设名称", text: $saveName)
            Button("保存") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将保存当前音色、情绪、语速和所有高级参数。")
        }
        .alert("无法保存预设", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var selectedName: String {
        guard let selectedID = store.selectedID,
              let preset = store.presets.first(where: { $0.id == selectedID }) else {
            return "自定义"
        }
        return preset.name
    }

    private var suggestedName: String {
        let emotion = generation.emotion.displayName
        return "\(emotion) · \(voiceLibrary.selectedVoice?.name ?? "新预设")"
    }

    private func apply(_ preset: GenerationPreset) {
        generation.apply(preset.parameters)
        if voiceLibrary.profiles.contains(where: { $0.id == preset.voiceID }) {
            voiceLibrary.selectedID = preset.voiceID
        }
        store.selectedID = preset.id
    }

    private func save() {
        guard let voiceID = voiceLibrary.selectedVoice?.id else { return }
        do {
            try store.save(
                name: saveName,
                voiceID: voiceID,
                parameters: generation.synthesisParameters
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
