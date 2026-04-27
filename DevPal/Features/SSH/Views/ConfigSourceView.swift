import SwiftUI
import AppKit

/// Raw text editor for ~/.ssh/config with syntax highlighting
struct ConfigSourceView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var sourceText = ""
    @State private var originalText = ""
    @State private var isSaving = false
    @State private var showSaveConfirm = false
    @State private var lineCount = 0

    private let configPath = NSHomeDirectory() + "/.ssh/config"

    var hasChanges: Bool {
        sourceText != originalText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Config 源码")
                    .font(.system(size: 14, weight: .medium))

                Text("~/.ssh/config")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if hasChanges {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.orange)
                    Text("已修改")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }

                Spacer()

                Text("\(lineCount) 行")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    loadConfig()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("重新加载")
                .disabled(hasChanges)

                Button {
                    showSaveConfirm = true
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasChanges || isSaving)
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(12)

            Divider()

            // Syntax-highlighted editor
            SSHConfigEditor(text: $sourceText)
                .onChange(of: sourceText) { _, newValue in
                    lineCount = newValue.components(separatedBy: "\n").count
                }

            // Warning bar
            if hasChanges {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("直接编辑源码请谨慎操作，保存前会自动创建备份")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("撤销修改") {
                        sourceText = originalText
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.06))
            }
        }
        .onAppear { loadConfig() }
        .alert("保存配置文件？", isPresented: $showSaveConfirm) {
            Button("取消", role: .cancel) { }
            Button("保存") {
                Task { await saveConfig() }
            }
        } message: {
            Text("将覆写 ~/.ssh/config 文件。变更前会自动备份。")
        }
    }

    private func loadConfig() {
        do {
            sourceText = try String(contentsOfFile: configPath, encoding: .utf8)
            originalText = sourceText
            lineCount = sourceText.components(separatedBy: "\n").count
        } catch {
            sourceText = ""
            originalText = ""
            viewModel.errorMessage = "加载配置文件失败: \(error.localizedDescription)"
        }
    }

    private func saveConfig() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let backupManager = BackupManager.shared
            _ = try await backupManager.createFullBackup()

            let data = sourceText.data(using: .utf8)!
            let tempURL = URL(fileURLWithPath: configPath + ".tmp")
            let configURL = URL(fileURLWithPath: configPath)
            try data.write(to: tempURL, options: .atomic)
            try FileManager.default.replaceItemAt(configURL, withItemAt: tempURL)

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: configPath
            )

            originalText = sourceText
            viewModel.successMessage = "配置文件已保存"
            await viewModel.refresh()
        } catch {
            viewModel.errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - NSTextView wrapper with SSH config syntax highlighting

private struct SSHConfigEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = .textBackgroundColor

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Initial content
        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            textView.selectedRanges = selectedRanges
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SSHConfigEditor
        weak var textView: NSTextView?
        private var isUpdating = false

        // SSH config keywords
        private static let sectionKeywords: Set<String> = ["Host", "Match"]
        private static let directiveKeywords: Set<String> = [
            "HostName", "User", "Port", "IdentityFile", "IdentitiesOnly",
            "ProxyJump", "ProxyCommand", "ForwardAgent", "AddKeysToAgent",
            "ServerAliveInterval", "ServerAliveCountMax", "ConnectTimeout",
            "StrictHostKeyChecking", "UserKnownHostsFile", "LogLevel",
            "Compression", "ControlMaster", "ControlPath", "ControlPersist",
            "LocalForward", "RemoteForward", "DynamicForward",
            "PreferredAuthentications", "PubkeyAuthentication",
            "PasswordAuthentication", "KbdInteractiveAuthentication",
            "ChallengeResponseAuthentication", "GSSAPIAuthentication",
            "HostKeyAlgorithms", "KexAlgorithms", "Ciphers", "MACs",
            "Include", "SendEnv", "SetEnv", "RequestTTY",
            "PermitLocalCommand", "LocalCommand", "VisualHostKey",
            "BatchMode", "CheckHostIP", "HashKnownHosts",
            "NumberOfPasswordPrompts", "TCPKeepAlive",
            "UpdateHostKeys", "CanonicalDomains", "CanonicalizeHostname",
            "AddressFamily", "BindAddress", "BindInterface",
            "EscapeChar", "ExitOnForwardFailure", "FingerprintHash",
            "GatewayPorts", "GlobalKnownHostsFile", "HostbasedAuthentication",
            "HostKeyAlias", "IPQoS", "NoHostAuthenticationForLocalhost",
            "PKCS11Provider", "RekeyLimit", "RevokedHostKeys",
            "StreamLocalBindMask", "StreamLocalBindUnlink",
            "Tunnel", "TunnelDevice", "XAuthLocation",
        ]

        init(parent: SSHConfigEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            applyHighlighting(to: textView)
            isUpdating = false
        }

        func applyHighlighting(to textView: NSTextView) {
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            guard let storage = textView.textStorage else { return }

            storage.beginEditing()

            // Reset to default
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: fullRange)

            let lines = text.components(separatedBy: "\n")
            var offset = 0

            for line in lines {
                let lineLength = (line as NSString).length
                let lineRange = NSRange(location: offset, length: lineLength)
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("#") {
                    // Comment — gray italic
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                    storage.addAttribute(.font, value: NSFont(descriptor: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontDescriptor.withSymbolicTraits(.italic), size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: lineRange)

                } else {
                    // Find keyword at start of line
                    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    if let keyword = parts.first.map(String.init) {
                        // Find keyword position in original line
                        if let kwRange = line.range(of: keyword) {
                            let nsKwRange = NSRange(kwRange, in: line)
                            let adjustedRange = NSRange(location: offset + nsKwRange.location, length: nsKwRange.length)

                            if Self.sectionKeywords.contains(keyword) {
                                // Host / Match — bold accent
                                storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: adjustedRange)
                                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), range: adjustedRange)

                                // Value part — also highlighted
                                if parts.count > 1, let valRange = line.range(of: String(parts[1])) {
                                    let nsValRange = NSRange(valRange, in: line)
                                    let adjustedValRange = NSRange(location: offset + nsValRange.location, length: nsValRange.length)
                                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: adjustedValRange)
                                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), range: adjustedValRange)
                                }

                            } else if Self.directiveKeywords.contains(keyword) {
                                // Directive keyword — blue
                                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: adjustedRange)

                                // Value — green
                                if parts.count > 1, let valRange = line.range(of: String(parts[1])) {
                                    let nsValRange = NSRange(valRange, in: line)
                                    let adjustedValRange = NSRange(location: offset + nsValRange.location, length: nsValRange.length)
                                    storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: adjustedValRange)
                                }
                            }
                        }
                    }
                }

                offset += lineLength + 1 // +1 for \n
            }

            storage.endEditing()
        }
    }
}
