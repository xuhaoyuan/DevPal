import SwiftUI

struct ConnectionTestView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("连通性测试")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    Task {
                        isTesting = true
                        await viewModel.testAllConnections()
                        isTesting = false
                    }
                } label: {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("全部测试", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)
            }
            .padding(12)

            Divider()

            if viewModel.configs.filter({ !$0.isGlobal }).isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无可测试的 Host 配置")
                        .foregroundColor(.secondary)
                    Text("请先在「Host 配置」中添加至少一个 Host")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.configs.filter { !$0.isGlobal }) { config in
                            testRow(config: config)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func testRow(config: SSHHostConfig) -> some View {
        let result = viewModel.testResults[config.host]

        return HStack {
            // Status indicator
            statusDot(result?.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.host)
                    .font(.system(size: 13, weight: .medium))
                Text(config.hostName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Result message
            if let result = result {
                resultText(result.status)
            }

            // Test button
            Button {
                Task { await viewModel.testConnection(for: config) }
            } label: {
                Text("测试")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func statusDot(_ status: ConnectionStatus?) -> some View {
        let status = status ?? .untested
        switch status {
        case .untested:
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 10, height: 10)
        case .testing:
            ProgressView().controlSize(.mini)
        case .success:
            Circle().fill(Color.green).frame(width: 10, height: 10)
        case .failed:
            Circle().fill(Color.red).frame(width: 10, height: 10)
        case .timeout:
            Circle().fill(Color.orange).frame(width: 10, height: 10)
        }
    }

    @ViewBuilder
    private func resultText(_ status: ConnectionStatus) -> some View {
        switch status {
        case .untested:
            EmptyView()
        case .testing:
            Text("测试中...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .success(let msg):
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(.green)
                .lineLimit(1)
                .frame(maxWidth: 250, alignment: .trailing)
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 11))
                .foregroundColor(.red)
                .lineLimit(2)
                .frame(maxWidth: 250, alignment: .trailing)
        case .timeout:
            Text("连接超时 (5s)")
                .font(.system(size: 11))
                .foregroundColor(.orange)
        }
    }
}
