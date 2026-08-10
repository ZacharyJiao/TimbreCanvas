import AppKit
import Foundation

@MainActor
enum FolderSelectionService {
    static func chooseOutputDirectory(current: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择语音导出文件夹"
        panel.prompt = "选择"
        panel.directoryURL = current
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
