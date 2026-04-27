import SwiftUI

struct PortManagerView: View {
    @State private var ports: [PortUsage] = []
    @State private var isLoading = false
    @State private var listenOnly = true
    @State private var searchText = ""
    @State private var protocolFilter: ProtocolFilter = .all
    @State private var killingPID: Int32?
    @State private var killTarget: PortUsage?
    @State private var forceKill = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    enum ProtocolFilter: String, CaseIterable {
        case all = "全部", tcp = "TCP", udp = "UDP"
    }

    var filteredPorts: [PortUsage] {
        ports.filter { p in
            let q = searchText.lowercased()
            let matchesSearch = q.isEmpty ||
                String(p.port).contains(q) ||
                p.processName.lowercased().contains(q) ||
                p.address.lowercased().contains(q) ||
                String(p.pid).contains(q)
            let matchesProto: Bool = {
                switch protocolFilter {
                case .all: return true
                case .tcp: return p.protocol == "tcp"
                case .udp: return p.protocol == "udp"
                }
            }()
            return matchesSearch && matchesProto
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = errorMessage { messageBar(error, isError: true) }
            if let success = successMessage { messageBar(success, isError: false) }

            if isLoading && ports.isEmpty {
                Spacer()
                ProgressView("正在扫描端口...")
                Spacer()
            } else if filteredPorts.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(ports.isEmpty ? "暂无端口数据" : "无匹配结果")
                        .foregroundColor(.secondary)
                    if ports.isEmpty {
                        Button("扫描端口") { Task { await scan() } }
                            .buttonStyle(.bordered)
                    }
                }
                Spacer()
            } else {
                portList
            }

            Divider()
            statusBar
        }
        .task { await scan() }
        .alert("终止进程", isPresented: .constant(killTarget != nil), presenting: killTarget) { target in
            Button("取消", role: .cancel) { killTarget = nil }
            Button("普通终止 (SIGTERM)") {
                Task { await kill(target, force: false) }
            }
            Button("强制终止 (SIGKILL)", role: .destructive) {
                Task { await kill(target, force: true) }
            }
        } message: { target in
            Text("将终止进程:\n\(target.processName) (PID \(target.pid))\n监听端口 \(target.port)")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("端口占用")
                .font(.system(size: 14, weight: .medium))
                .fixedSize()

            // Scrollable middle section: search + filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                        TextField("端口/进程/PID", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                    .fixedSize()

                    Picker("", selection: $protocolFilter) {
                        ForEach(ProtocolFilter.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .fixedSize()

                    Toggle("仅监听", isOn: $listenOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .onChange(of: listenOnly) { _, _ in Task { await scan() } }
                        .fixedSize()
                }
                .padding(.vertical, 1)
            }

            Button {
                Task { await scan() }
            } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
            .fixedSize()
        }
        .padding(12)
    }

    // MARK: - Port List

    private let colPort: CGFloat = 150
    private let colProto: CGFloat = 50
    private let colAddr: CGFloat = 140
    private let colProc: CGFloat = 180
    private let colPID: CGFloat = 70
    private let colUser: CGFloat = 70
    private let colAction: CGFloat = 80
    private var tableMinWidth: CGFloat {
        colPort + colProto + colAddr + colProc + colPID + colUser + colAction + 8 * 6 + 24
    }

    private var portList: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Text("端口").frame(width: colPort, alignment: .leading)
                    Text("协议").frame(width: colProto, alignment: .leading)
                    Text("地址").frame(width: colAddr, alignment: .leading)
                    Text("进程").frame(width: colProc, alignment: .leading)
                    Text("PID").frame(width: colPID, alignment: .leading)
                    Text("用户").frame(width: colUser, alignment: .leading)
                    Text("操作").frame(width: colAction, alignment: .leading)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredPorts.enumerated()), id: \.element.id) { index, port in
                        portRow(port)
                            .background(index % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    }
                }
            }
            .frame(minWidth: tableMinWidth)
        }
    }

    private func portRow(_ port: PortUsage) -> some View {
        HStack(spacing: 8) {
            // Port + common name badge
            HStack(spacing: 4) {
                Text("\(port.port)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if let known = PortScanner.commonPorts[port.port] {
                    Text(known)
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.12)))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .help("常用端口: \(known)")
                }
            }
            .frame(width: colPort, alignment: .leading)

            // Protocol
            Text(port.protocol.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(port.protocol == "tcp" ? .green : .orange)
                .frame(width: colProto, alignment: .leading)

            // Address
            Text(port.address)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(port.isLocalhost ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: colAddr, alignment: .leading)

            // Process
            Text(port.processName)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(width: colProc, alignment: .leading)

            // PID
            Text("\(port.pid)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: colPID, alignment: .leading)

            // User
            Text(port.user)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: colUser, alignment: .leading)

            // Actions
            HStack(spacing: 4) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(port.port)", forType: .string)
                    successMessage = "已复制端口号 \(port.port)"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("复制端口号")

                Button {
                    killTarget = port
                } label: {
                    if killingPID == port.pid {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "xmark.octagon")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.plain)
                .help("终止进程")
                .disabled(killingPID != nil)
            }
            .frame(width: colAction, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu {
            Button("复制端口号") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(port.port)", forType: .string)
            }
            Button("复制 PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(port.pid)", forType: .string)
            }
            Button("复制进程名") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(port.processName, forType: .string)
            }
            Divider()
            Button("终止进程", role: .destructive) {
                killTarget = port
            }
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack {
            Text("\(filteredPorts.count) / \(ports.count) 个端口")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(listenOnly ? "仅显示 LISTEN 状态" : "显示所有连接")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func messageBar(_ text: String, isError: Bool) -> some View {
        HStack {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
            Text(text).font(.system(size: 12))
            Spacer()
            Button {
                errorMessage = nil
                successMessage = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
    }

    // MARK: - Actions

    private func scan() async {
        isLoading = true
        defer { isLoading = false }
        ports = await PortScanner.scan(listenOnly: listenOnly)
    }

    private func kill(_ port: PortUsage, force: Bool) async {
        killingPID = port.pid
        killTarget = nil
        defer { killingPID = nil }

        do {
            try await PortScanner.kill(pid: port.pid, force: force)
            successMessage = "已\(force ? "强制" : "")终止 \(port.processName) (PID \(port.pid))"
            try? await Task.sleep(nanoseconds: 500_000_000)
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
