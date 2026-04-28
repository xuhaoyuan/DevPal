import SwiftUI
import UniformTypeIdentifiers

struct HiddenFilesMainView: View {
    @ObservedObject var viewModel: HiddenFilesViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Message bars
            if let error = viewModel.errorMessage {
                messageBar(text: error, isError: true)
            }
            if let success = viewModel.successMessage {
                messageBar(text: success, isError: false)
            }

            ScrollView {
                VStack(spacing: 20) {
                    // Main toggle card
                    toggleCard

                    // Shortcuts section
                    shortcutsSection

                    // Drop zone for single file management
                    dropZoneSection
                }
                .padding(16)
            }
        }
    }

    // MARK: - Toggle Card

    private var toggleCard: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.isShowingHiddenFiles ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 40))
                .foregroundColor(viewModel.isShowingHiddenFiles ? .accentColor : .secondary)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isShowingHiddenFiles)

            Text("隐藏文件当前：\(viewModel.isShowingHiddenFiles ? "已显示" : "已隐藏")")
                .font(.system(size: 16, weight: .medium))

            Button {
                Task { await viewModel.toggleHiddenFiles() }
            } label: {
                if viewModel.isToggling {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 120, height: 28)
                } else {
                    Text(viewModel.isShowingHiddenFiles ? "隐藏全部" : "显示全部")
                        .frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isToggling)

            Text("切换后将重启 Finder，当前窗口会短暂闪动")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Shortcuts Section

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常用隐藏目录")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 2) {
                ForEach(viewModel.shortcuts) { shortcut in
                    shortcutRow(shortcut)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func shortcutRow(_ shortcut: HiddenFileShortcut) -> some View {
        HStack(spacing: 10) {
            Image(systemName: shortcut.icon)
                .font(.system(size: 14))
                .foregroundColor(shortcut.exists ? .accentColor : .secondary.opacity(0.4))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(shortcut.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(shortcut.exists ? .primary : .secondary.opacity(0.5))
                Text(shortcut.label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !shortcut.exists {
                Text("不存在")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                Button("打开") {
                    viewModel.openInFinder(shortcut)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .contextMenu {
                    Button("在 Finder 中打开") { viewModel.openInFinder(shortcut) }
                    Button("在终端中打开") { viewModel.openInTerminal(shortcut) }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Drop Zone

    private var dropZoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("单文件隐藏管理")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            // Dropped files list
            if !viewModel.droppedFiles.isEmpty {
                VStack(spacing: 2) {
                    ForEach(viewModel.droppedFiles) { file in
                        droppedFileRow(file)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }

            // Drop target
            FileDropZone { urls in
                for url in urls {
                    Task { await viewModel.handleDroppedFile(url: url) }
                }
            }
        }
    }

    private func droppedFileRow(_ file: DroppedFileInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: file.isHidden ? "eye.slash" : "eye")
                .font(.system(size: 13))
                .foregroundColor(file.isHidden ? .orange : .green)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                Text(file.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(file.isHidden ? "已隐藏" : "可见")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(file.isHidden ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
                )
                .foregroundColor(file.isHidden ? .orange : .green)

            Button(file.isHidden ? "取消隐藏" : "隐藏") {
                Task { await viewModel.toggleFileHidden(file) }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button {
                viewModel.removeDroppedFile(file)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Message Bar

    private func messageBar(text: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text)
                .font(.system(size: 12))
            Spacer()
            Button {
                viewModel.clearMessages()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
    }
}

// MARK: - File Drop Zone

struct FileDropZone: View {
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.3))
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                )

            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                Text("拖拽文件到此处，管理隐藏属性")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 80)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            onDrop([url])
                        }
                    }
                }
            }
            return true
        }
    }
}
