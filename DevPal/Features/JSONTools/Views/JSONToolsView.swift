import SwiftUI

struct JSONToolsView: View {
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var indentSize: IndentSize = .two
    @State private var sortKeys = false
    @State private var escapeUnicode = false
    @State private var errorMessage: String?
    @State private var stats: JSONStats?
    @State private var copied = false

    enum IndentSize: Int, CaseIterable, Identifiable {
        case zero = 0, two = 2, four = 4, tab = -1
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .zero: return "压缩"
            case .two: return "2 空格"
            case .four: return "4 空格"
            case .tab: return "Tab"
            }
        }
    }

    struct JSONStats {
        let keys: Int
        let values: Int
        let depth: Int
        let size: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                inputPane
                    .frame(minWidth: 300)
                outputPane
                    .frame(minWidth: 300)
            }
            Divider()
            statusBar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("JSON 格式化")
                .font(.system(size: 14, weight: .medium))

            Spacer()

            Picker("缩进", selection: $indentSize) {
                ForEach(IndentSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: indentSize) { _, _ in format() }

            Toggle("排序键", isOn: $sortKeys)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onChange(of: sortKeys) { _, _ in format() }

            Toggle("转义 Unicode", isOn: $escapeUnicode)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .onChange(of: escapeUnicode) { _, _ in format() }
        }
        .padding(12)
    }

    private var inputPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("输入")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    inputText = NSPasteboard.general.string(forType: .string) ?? ""
                    format()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.mini)
                Button {
                    inputText = sampleJSON
                    format()
                } label: {
                    Label("示例", systemImage: "doc.text")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.mini)
                Button {
                    inputText = ""
                    outputText = ""
                    errorMessage = nil
                    stats = nil
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(8)

            TextEditor(text: $inputText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .onChange(of: inputText) { _, _ in format() }
        }
    }

    private var outputPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("输出")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                if errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outputText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    if copied {
                        Label("已复制", systemImage: "checkmark")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    } else {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(outputText.isEmpty)

                Button {
                    indentSize = .zero
                    format()
                } label: {
                    Label("压缩", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(inputText.isEmpty)
            }
            .padding(8)

            if let error = errorMessage {
                ScrollView {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                }
                .background(Color.red.opacity(0.05))
            } else {
                ReadOnlyTextView(text: outputText, font: .monospacedSystemFont(ofSize: 12, weight: .regular))
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let s = stats {
                Label("\(s.keys) 键", systemImage: "key")
                Label("\(s.values) 值", systemImage: "doc.text")
                Label("深度 \(s.depth)", systemImage: "arrow.down.to.line")
                Label("\(byteFormat(s.size))", systemImage: "scalemass")
            } else if !inputText.isEmpty && errorMessage == nil {
                Text("等待输入...")
            }
            Spacer()
            Text("\(inputText.count) → \(outputText.count) 字符")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Logic

    private func format() {
        errorMessage = nil
        stats = nil
        outputText = ""

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let data = trimmed.data(using: .utf8) else {
            errorMessage = "无法编码为 UTF-8"
            return
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            var options: JSONSerialization.WritingOptions = []
            if indentSize != .zero { options.insert(.prettyPrinted) }
            if sortKeys { options.insert(.sortedKeys) }
            if !escapeUnicode { options.insert(.withoutEscapingSlashes) }

            let outData = try JSONSerialization.data(withJSONObject: obj, options: options)
            var result = String(data: outData, encoding: .utf8) ?? ""

            // Adjust indent if not 2 (Apple's default is 2)
            if indentSize == .four {
                result = result.replacingOccurrences(of: "  ", with: "    ")
            } else if indentSize == .tab {
                result = result.replacingOccurrences(of: "  ", with: "\t")
            }

            outputText = result
            stats = analyze(obj, originalSize: outData.count)
        } catch {
            errorMessage = "JSON 解析失败: \(error.localizedDescription)"
        }
    }

    private func analyze(_ obj: Any, originalSize: Int) -> JSONStats {
        var keys = 0
        var values = 0
        var maxDepth = 0

        func walk(_ node: Any, depth: Int) {
            maxDepth = max(maxDepth, depth)
            if let dict = node as? [String: Any] {
                keys += dict.count
                for (_, v) in dict {
                    walk(v, depth: depth + 1)
                }
            } else if let arr = node as? [Any] {
                for v in arr {
                    walk(v, depth: depth + 1)
                }
            } else {
                values += 1
            }
        }
        walk(obj, depth: 1)
        return JSONStats(keys: keys, values: values, depth: maxDepth, size: originalSize)
    }

    private func byteFormat(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / 1024 / 1024)
    }

    private let sampleJSON = """
    {"name":"DevPal","version":"1.0.0","tags":["dev","ssh","macos"],"author":{"name":"x","email":"x@example.com"},"features":{"ssh":true,"ports":true,"env":true},"created":"2026-04-27"}
    """
}
