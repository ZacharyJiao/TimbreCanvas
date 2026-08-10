import SwiftUI

struct VoiceSidebarView: View {
    @ObservedObject var store: VoiceLibraryStore
    let importAction: () -> Void

    @State private var profileToDelete: VoiceProfile?
    @State private var profileToRename: VoiceProfile?
    @State private var renameText = ""

    var body: some View {
        List(selection: $store.selectedID) {
            if let error = store.persistenceErrorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityLabel("音色清单错误：\(error)")
                }
            }
            Section("默认声音") {
                ForEach(store.filteredBuiltIns) { voice in
                    row(voice)
                }
            }
            Section("我的声音") {
                if store.filteredCustom.isEmpty {
                    Text(store.searchText.isEmpty ? "导入参考音频来创建音色" : "没有匹配的音色")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.filteredCustom) { voice in
                        row(voice)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .frame(minWidth: 220)
        .navigationSplitViewColumnWidth(230)
        .navigationTitle("纸艺工作台")
        .navigationSubtitle("原生文本转语音")
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "搜索音色")
        .safeAreaInset(edge: .bottom) {
            Button(action: importAction) {
                Label("导入新音色", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    StudioDesign.paper
                    PaperTexture(opacity: 0.36)
                }
                .overlay(alignment: .top) { Divider() }
            }
            .accessibilityIdentifier("voice.import")
        }
        .alert("删除这个音色？", isPresented: deleteBinding, presenting: profileToDelete) { profile in
            Button("删除", role: .destructive) { try? store.delete(id: profile.id) }
            Button("取消", role: .cancel) {}
        } message: { profile in
            Text("“\(profile.name)”的本地音色文件也会被删除。")
        }
        .alert("重命名音色", isPresented: renameBinding, presenting: profileToRename) { profile in
            TextField("音色名称", text: $renameText)
            Button("保存") { try? store.rename(id: profile.id, to: renameText) }
            Button("取消", role: .cancel) {}
        }
    }

    private func row(_ voice: VoiceProfile) -> some View {
        HStack(spacing: 4) {
            VoiceRowView(voice: voice)
            Spacer(minLength: 4)
            if voice.kind == .custom {
                Button {
                    beginRename(voice)
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("重命名“\(voice.name)”")
                .accessibilityLabel("重命名 \(voice.name)")
            }
        }
            .tag(voice.id)
            .listRowBackground(
                store.selectedID == voice.id
                    ? StudioDesign.accent.opacity(0.13)
                    : Color.clear
            )
            .contextMenu {
                Button("重命名") {
                    beginRename(voice)
                }
                if voice.kind == .custom {
                    Divider()
                    Button("删除", role: .destructive) { profileToDelete = voice }
                }
            }
    }

    private func beginRename(_ voice: VoiceProfile) {
        profileToRename = voice
        renameText = voice.name
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { profileToRename != nil },
            set: { if !$0 { profileToRename = nil } }
        )
    }
}
