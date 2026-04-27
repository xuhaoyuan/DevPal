import SwiftUI

/// SSH verbose diagnostics view - parses ssh -vvv output into readable steps
struct DiagnosticView: View {
    @ObservedObject var viewModel: SSHViewModel
    let config: SSHHostConfig
    @Environment(\.dismiss) private var dismiss

    @State private var isDiagnosing = false
    @State private var rawOutput = ""
    @State private var steps: [DiagnosticStep] = []
    @State private var showRawOutput = false

    struct DiagnosticStep: Identifiable {
        let id = UUID()
        let phase: String
        let detail: String
        let status: StepStatus

        enum StepStatus {
            case success, failed, info
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("连接诊断: \(config.host)")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if isDiagnosing {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在诊断连接...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("ssh -vvv -T \(config.user.isEmpty ? "git" : config.user)@\(config.host)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if steps.isEmpty && rawOutput.isEmpty {
                Spacer()
                Button("开始诊断") {
                    Task { await runDiagnosis() }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            } else {
                // Toggle
                HStack {
                    Picker("", selection: $showRawOutput) {
                        Text("步骤分析").tag(false)
                        Text("原始输出").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    Spacer()
                    Button {
                        Task { await runDiagnosis() }
                    } label: {
                        Label("重新诊断", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)

                Divider()

                if showRawOutput {
                    // Raw output
                    ScrollView {
                        Text(rawOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else {
                    // Parsed steps
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(steps) { step in
                                stepRow(step)
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    private func stepRow(_ step: DiagnosticStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Status icon
            switch step.status {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            case .info:
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.phase)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(step.status == .failed ? .red : .primary)
                Text(step.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(step.status == .failed ? Color.red.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Diagnosis

    private func runDiagnosis() async {
        isDiagnosing = true
        steps = []
        rawOutput = ""
        defer { isDiagnosing = false }

        let host = config.host
        let user = config.user.isEmpty ? "git" : config.user
        let port = config.port ?? 22

        rawOutput = await SSHTestRunner.shared.diagnose(host: host, user: user, port: port)
        steps = parseVerboseOutput(rawOutput)
    }

    /// Parse ssh -vvv output into diagnostic steps
    private func parseVerboseOutput(_ output: String) -> [DiagnosticStep] {
        var steps: [DiagnosticStep] = []
        let lines = output.components(separatedBy: "\n")

        var dnsResolved = false
        var tcpConnected = false
        var sshVersion = ""
        var authMethods: [String] = []
        var triedKeys: [String] = []
        var authSuccess = false
        var authFailed = false
        var errorMessage = ""

        for line in lines {
            let lower = line.lowercased()

            // DNS resolution
            if lower.contains("connecting to") && lower.contains("port") {
                dnsResolved = true
                steps.append(DiagnosticStep(
                    phase: "DNS 解析",
                    detail: line.replacingOccurrences(of: "debug1: ", with: ""),
                    status: .success
                ))
            }

            // TCP connection
            if lower.contains("connection established") {
                tcpConnected = true
                steps.append(DiagnosticStep(
                    phase: "TCP 连接",
                    detail: "连接已建立",
                    status: .success
                ))
            }

            // SSH version
            if lower.contains("remote software version") {
                sshVersion = line.replacingOccurrences(of: "debug1: ", with: "")
                steps.append(DiagnosticStep(
                    phase: "SSH 协议",
                    detail: sshVersion,
                    status: .info
                ))
            }

            // Key exchange
            if lower.contains("kex: algorithm:") || lower.contains("host key algorithm:") {
                steps.append(DiagnosticStep(
                    phase: "密钥协商",
                    detail: line.replacingOccurrences(of: "debug2: ", with: "")
                        .replacingOccurrences(of: "debug1: ", with: ""),
                    status: .info
                ))
            }

            // Authentication methods
            if lower.contains("authentications that can continue") {
                let methods = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
                authMethods = methods.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                steps.append(DiagnosticStep(
                    phase: "可用认证方式",
                    detail: methods,
                    status: .info
                ))
            }

            // Trying specific identity file
            if lower.contains("trying private key:") || lower.contains("offering public key:") {
                let keyPath = line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? line
                triedKeys.append(keyPath)
                steps.append(DiagnosticStep(
                    phase: "尝试密钥",
                    detail: keyPath,
                    status: .info
                ))
            }

            // Authentication accepted
            if lower.contains("authentication succeeded") || lower.contains("accepted publickey") {
                authSuccess = true
                steps.append(DiagnosticStep(
                    phase: "认证成功",
                    detail: line.replacingOccurrences(of: "debug1: ", with: ""),
                    status: .success
                ))
            }

            // Authentication failure
            if lower.contains("permission denied") || lower.contains("authentication failed") {
                authFailed = true
                errorMessage = line
            }

            // Welcome message
            if lower.contains("welcome") || lower.contains("successfully authenticated") || lower.contains("hi ") {
                steps.append(DiagnosticStep(
                    phase: "服务器欢迎消息",
                    detail: line,
                    status: .success
                ))
            }

            // Connection refused / timeout
            if lower.contains("connection refused") {
                steps.append(DiagnosticStep(
                    phase: "连接被拒绝",
                    detail: "服务器拒绝了连接，请检查 HostName 和 Port 是否正确",
                    status: .failed
                ))
            }

            if lower.contains("connection timed out") || lower.contains("operation timed out") {
                steps.append(DiagnosticStep(
                    phase: "连接超时",
                    detail: "无法连接到服务器，请检查网络或防火墙设置",
                    status: .failed
                ))
            }

            // Host key verification
            if lower.contains("host key verification failed") {
                steps.append(DiagnosticStep(
                    phase: "主机指纹验证失败",
                    detail: "known_hosts 中的指纹与服务器不匹配。可在「known_hosts」tab 中清理旧记录后重试",
                    status: .failed
                ))
            }
        }

        // Add failure summary
        if authFailed && !authSuccess {
            var suggestion = "认证失败"
            if !triedKeys.isEmpty {
                suggestion += "，已尝试 \(triedKeys.count) 把密钥"
            }
            suggestion += "。请确认：\n1. 公钥已添加到平台\n2. IdentityFile 指向正确的密钥\n3. 多账号场景下设置了 IdentityAgent none"
            steps.append(DiagnosticStep(
                phase: "认证失败",
                detail: suggestion,
                status: .failed
            ))
        }

        // If no steps were generated, add a generic one
        if steps.isEmpty {
            steps.append(DiagnosticStep(
                phase: "诊断完成",
                detail: "未能解析详细步骤，请查看「原始输出」获取完整信息",
                status: .info
            ))
        }

        return steps
    }
}
