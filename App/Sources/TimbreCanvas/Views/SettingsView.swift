import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("推理引擎", value: "IndexTTS 2")
            LabeledContent("运行方式", value: "本机常驻进程")
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
