import SwiftUI

struct ProxyMainView: View {
    @StateObject private var viewModel = ProxyViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Message bars
            if let error = viewModel.errorMessage {
                messageBar(text: error, isError: true)
            }
            if let success = viewModel.successMessage {
                messageBar(text: success, isError: false)
            }

            // Toolbar
            HStack {
                // Service picker
                HStack(spacing: 6) {
                    Text("网络接口:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.selectedService) {
                        ForEach(viewModel.services) { service in
                            HStack {
                                Text(service.name)
                                if service.isActive {
                                    Text("(活跃)")
                                        .foregroundColor(.green)
                                        .font(.system(size: 10))
                                }
                            }.tag(service.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Spacer()

                Button {
                    Task { await viewModel.refreshProxyStatus() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await viewModel.runDiagnosis() }
                } label: {
                    if viewModel.isDiagnosing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("检测网络", systemImage: "waveform.path.ecg")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDiagnosing)
            }
            .padding(12)

            Divider()

            if viewModel.isLoading && viewModel.proxyStatuses.isEmpty {
                Spacer()
                ProgressView("读取代理状态...")
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Warning banner
                        if viewModel.showUnreachableWarning {
                            warningBanner
                        }

                        // Proxy status cards
                        proxyStatusSection

                        // Action buttons
                        actionButtons

                        // Diagnosis
                        if !viewModel.diagnosisItems.isEmpty {
                            diagnosisSection
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onChange(of: viewModel.selectedService) {
            Task { await viewModel.refreshProxyStatus() }
        }
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("检测到代理已开启但服务不可达")
                    .font(.system(size: 13, weight: .medium))
                Text("这很可能是代理工具已关闭但系统设置未清除导致的断网，建议点击「关闭所有代理」")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Proxy Status Section

    private var proxyStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("代理状态")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 2) {
                ForEach(viewModel.proxyStatuses) { status in
                    proxyStatusRow(status)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func proxyStatusRow(_ status: ProxyStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.type.icon)
                .font(.system(size: 13))
                .foregroundColor(status.enabled ? .accentColor : .secondary.opacity(0.4))
                .frame(width: 20)

            Text(status.type.rawValue)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 100, alignment: .leading)

            // Status dot
            Circle()
                .fill(status.enabled ? Color.green : Color.red.opacity(0.4))
                .frame(width: 8, height: 8)

            Text(status.enabled ? "开启" : "关闭")
                .font(.system(size: 11))
                .foregroundColor(status.enabled ? .primary : .secondary)
                .frame(width: 30, alignment: .leading)

            if status.enabled {
                Text(status.displayAddress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if status.isLocalProxy {
                    Text("本地代理")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.12)))
                        .foregroundColor(.blue)
                }

                // Reachability indicator
                if let reachable = status.reachable {
                    if reachable {
                        Label("可达", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    } else {
                        Label("不可达", systemImage: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.disableAllProxies() }
            } label: {
                if viewModel.isDisabling {
                    ProgressView().controlSize(.small).frame(width: 120)
                } else {
                    Label("关闭所有代理", systemImage: "xmark.shield")
                        .frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(viewModel.isDisabling || !viewModel.hasAnyProxyEnabled)

            Button {
                Task { await viewModel.resetToDefault() }
            } label: {
                Label("恢复默认", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.isDisabling)

            Spacer()
        }
    }

    // MARK: - Diagnosis Section

    private var diagnosisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("网络诊断")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 2) {
                ForEach(viewModel.diagnosisItems) { item in
                    diagnosisRow(item)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private func diagnosisRow(_ item: DiagnosisItem) -> some View {
        HStack(spacing: 10) {
            diagnosisIcon(item.status)
                .frame(width: 16)

            Text(item.label)
                .font(.system(size: 12))
                .frame(width: 160, alignment: .leading)

            switch item.status {
            case .pending:
                Text("等待中")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            case .checking:
                ProgressView().controlSize(.mini)
                Text("检测中...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            case .success:
                Text("正常")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            case .failed:
                Text("不通")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            if let latency = item.latency {
                Text(latency)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func diagnosisIcon(_ status: DiagnosisStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.secondary.opacity(0.3))
                .font(.system(size: 12))
        case .checking:
            ProgressView().controlSize(.mini)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
        }
    }

    // MARK: - Message Bar

    private func messageBar(text: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text)
                .font(.system(size: 12))
            Spacer()
            Button { viewModel.clearMessages() } label: {
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
