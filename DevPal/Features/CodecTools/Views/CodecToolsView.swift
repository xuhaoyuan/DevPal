import SwiftUI
import CryptoKit

struct CodecToolsView: View {
    @State private var selectedTool: Tool = .base64

    enum Tool: String, CaseIterable, Identifiable {
        case base64 = "Base64"
        case url = "URL"
        case jwt = "JWT"
        case hash = "Hash"
        case unicode = "Unicode"
        case htmlEntities = "HTML"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .base64: return "doc.text.below.ecg"
            case .url: return "link"
            case .jwt: return "person.badge.key"
            case .hash: return "number"
            case .unicode: return "character"
            case .htmlEntities: return "chevron.left.slash.chevron.right"
            }
        }
        var subtitle: String {
            switch self {
            case .base64: return "Base64 编解码"
            case .url: return "URL 编解码"
            case .jwt: return "JWT Token 解码"
            case .hash: return "MD5 / SHA"
            case .unicode: return "Unicode 转义"
            case .htmlEntities: return "HTML 实体"
            }
        }
    }

    var body: some View {
        PersistentSplitView(id: "codec", minWidth: 120, maxWidth: 220, defaultWidth: 150) {
            // Sidebar
            VStack(spacing: 2) {
                ForEach(Tool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 12))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                Text(tool.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTool == tool ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .foregroundColor(selectedTool == tool ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        } content: {
            // Detail
            Group {
                switch selectedTool {
                case .base64: Base64Tool()
                case .url: URLTool()
                case .jwt: JWTTool()
                case .hash: HashTool()
                case .unicode: UnicodeTool()
                case .htmlEntities: HTMLEntitiesTool()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Shared Components

private struct CodecPanel<Output: View>: View {
    let title: String
    @Binding var input: String
    let output: () -> Output
    var inputPlaceholder: String = "在此输入..."

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.mini)
                Button {
                    input = ""
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("输入").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(input.count) 字符").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(8)
                    TextEditor(text: $input)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .frame(minWidth: 200)

                output()
                    .frame(minWidth: 200)
            }
        }
    }
}

private struct OutputPane: View {
    let title: String
    let content: String
    var error: String? = nil

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                if error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red).font(.system(size: 10))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    if copied {
                        Label("已复制", systemImage: "checkmark").font(.system(size: 11)).foregroundColor(.green)
                    } else {
                        Label("复制", systemImage: "doc.on.doc").font(.system(size: 11))
                    }
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .disabled(content.isEmpty)
            }
            .padding(8)

            if let error = error {
                ScrollView {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.red.opacity(0.05))
            } else {
                ReadOnlyTextView(text: content.isEmpty ? "（无输出）" : content, font: .monospacedSystemFont(ofSize: 12, weight: .regular))
            }
        }
    }
}

// MARK: - Base64

private struct Base64Tool: View {
    @State private var input = ""
    @State private var urlSafe = false

    var encoded: String {
        guard !input.isEmpty else { return "" }
        let data = input.data(using: .utf8) ?? Data()
        var result = data.base64EncodedString()
        if urlSafe {
            result = result
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return result
    }

    var decoded: (String, String?) {
        guard !input.isEmpty else { return ("", nil) }
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "-", with: "+")
             .replacingOccurrences(of: "_", with: "/")
        // Pad
        let pad = 4 - (s.count % 4)
        if pad < 4 { s += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: s) else {
            return ("", "无法解码：不是有效的 Base64")
        }
        if let str = String(data: data, encoding: .utf8) {
            return (str, nil)
        }
        return (data.map { String(format: "%02x", $0) }.joined(separator: " "), "二进制数据（显示为 hex）")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Base64 编解码").font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("URL Safe", isOn: $urlSafe)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11)) }
                .buttonStyle(.bordered).controlSize(.mini)
                Button { input = "" } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("输入").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }.padding(8)
                    TextEditor(text: $input)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(4)
                }
                .frame(minWidth: 200)

                VStack(spacing: 0) {
                    OutputPane(title: "编码 →", content: encoded)
                    Divider()
                    OutputPane(title: "解码 ←", content: decoded.0, error: decoded.1)
                }
                .frame(minWidth: 200)
            }
        }
    }
}

// MARK: - URL

private struct URLTool: View {
    @State private var input = ""
    @State private var encodeAll = false

    var encoded: String {
        let allowed: CharacterSet = encodeAll
            ? CharacterSet.alphanumerics
            : CharacterSet.urlQueryAllowed
        return input.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
    var decoded: String { input.removingPercentEncoding ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("URL 编解码").font(.system(size: 14, weight: .medium))
                Spacer()
                Toggle("全部转义", isOn: $encodeAll)
                    .toggleStyle(.checkbox).font(.system(size: 11))
                    .help("启用时连字母数字以外都转义")
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11)) }
                .buttonStyle(.bordered).controlSize(.mini)
                Button { input = "" } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("输入").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }.padding(8)
                    TextEditor(text: $input)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(4)
                }
                .frame(minWidth: 200)

                VStack(spacing: 0) {
                    OutputPane(title: "URL 编码 →", content: encoded)
                    Divider()
                    OutputPane(title: "URL 解码 ←", content: decoded)
                }
                .frame(minWidth: 200)
            }
        }
    }
}

// MARK: - JWT

private struct JWTTool: View {
    @State private var input = ""

    struct DecodedJWT {
        let header: String
        let payload: String
        let signature: String
        let alg: String?
        let exp: Date?
        let iat: Date?
    }

    var decoded: (DecodedJWT?, String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        let parts = trimmed.components(separatedBy: ".")
        guard parts.count == 3 else {
            return (nil, "JWT 格式错误：应有 3 段（header.payload.signature），实际 \(parts.count) 段")
        }
        guard let header = decodeJWTPart(parts[0]),
              let payload = decodeJWTPart(parts[1]) else {
            return (nil, "Base64 解码失败")
        }

        let headerJSON = prettyJSON(header) ?? header
        let payloadJSON = prettyJSON(payload) ?? payload

        // Extract metadata
        var alg: String?
        var exp: Date?
        var iat: Date?
        if let data = header.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            alg = dict["alg"] as? String
        }
        if let data = payload.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = dict["exp"] as? TimeInterval { exp = Date(timeIntervalSince1970: v) }
            if let v = dict["iat"] as? TimeInterval { iat = Date(timeIntervalSince1970: v) }
        }

        return (DecodedJWT(
            header: headerJSON,
            payload: payloadJSON,
            signature: parts[2],
            alg: alg,
            exp: exp,
            iat: iat
        ), nil)
    }

    private func decodeJWTPart(_ s: String) -> String? {
        var padded = s.replacingOccurrences(of: "-", with: "+")
                      .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (padded.count % 4)
        if pad < 4 { padded += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func prettyJSON(_ s: String) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JWT Token 解码").font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11)) }
                .buttonStyle(.bordered).controlSize(.mini)
                Button { input = "" } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text("Token").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    Spacer()
                }.padding(8)
                TextEditor(text: $input)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(maxHeight: 100)

                Divider()

                if let error = decoded.1 {
                    HStack {
                        Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                        Text(error).font(.system(size: 12)).foregroundColor(.red)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.05))
                    Spacer()
                } else if let jwt = decoded.0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Metadata badges
                            HStack(spacing: 8) {
                                if let alg = jwt.alg {
                                    badge(text: "alg: \(alg)", color: .blue)
                                }
                                if let iat = jwt.iat {
                                    badge(text: "签发: \(formatDate(iat))", color: .green)
                                }
                                if let exp = jwt.exp {
                                    let expired = exp < Date()
                                    badge(text: "过期: \(formatDate(exp))", color: expired ? .red : .orange)
                                    if expired {
                                        badge(text: "已过期", color: .red)
                                    }
                                }
                            }

                            sectionHeader("Header (header.alg)", color: .red)
                            codeBlock(jwt.header, color: .red)

                            sectionHeader("Payload (claims)", color: .purple)
                            codeBlock(jwt.payload, color: .purple)

                            sectionHeader("Signature", color: .blue)
                            codeBlock(jwt.signature, color: .blue)

                            HStack(spacing: 4) {
                                Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(.secondary)
                                Text("注意：此工具不验证签名有效性，仅做 Base64 解码。")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 30)).foregroundColor(.secondary)
                        Text("粘贴一个 JWT Token 进行解码")
                            .foregroundColor(.secondary).font(.system(size: 12))
                    }
                    Spacer()
                }
            }
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.12)))
            .foregroundColor(color)
    }

    private func sectionHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
    }

    private func codeBlock(_ content: String, color: Color) -> some View {
        Text(content)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.06)))
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Hash

private struct HashTool: View {
    @State private var input = ""

    private func hashes(of text: String) -> [(String, String)] {
        guard let data = text.data(using: .utf8) else { return [] }
        let md5 = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha384 = SHA384.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sha512 = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return [
            ("MD5", md5),
            ("SHA-1", sha1),
            ("SHA-256", sha256),
            ("SHA-384", sha384),
            ("SHA-512", sha512),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hash 计算").font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11)) }
                .buttonStyle(.bordered).controlSize(.mini)
                Button { input = "" } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text("输入").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    Spacer()
                    Text("\(input.utf8.count) 字节").font(.system(size: 10)).foregroundColor(.secondary)
                }
                .padding(8)
                TextEditor(text: $input)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(maxHeight: 120)

                Divider()

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(hashes(of: input), id: \.0) { algo, hash in
                            hashRow(algo: algo, hash: hash)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func hashRow(algo: String, hash: String) -> some View {
        HStack(spacing: 8) {
            Text(algo)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 70, alignment: .leading)
                .foregroundColor(.accentColor)
            Text(hash)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hash, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Unicode

private struct UnicodeTool: View {
    @State private var input = ""

    var escaped: String {
        input.unicodeScalars.map { scalar -> String in
            if scalar.isASCII { return String(scalar) }
            return String(format: "\\u%04x", scalar.value)
        }.joined()
    }

    var unescaped: String {
        var result = ""
        var i = input.startIndex
        while i < input.endIndex {
            if input[i] == "\\",
               input.index(after: i) < input.endIndex,
               input[input.index(after: i)] == "u",
               input.distance(from: i, to: input.endIndex) >= 6 {
                let hexStart = input.index(i, offsetBy: 2)
                let hexEnd = input.index(hexStart, offsetBy: 4)
                let hex = String(input[hexStart..<hexEnd])
                if let value = UInt32(hex, radix: 16),
                   let scalar = Unicode.Scalar(value) {
                    result.append(Character(scalar))
                    i = hexEnd
                    continue
                }
            }
            result.append(input[i])
            i = input.index(after: i)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Unicode 转义").font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11)) }
                .buttonStyle(.bordered).controlSize(.mini)
                Button { input = "" } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("输入").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }.padding(8)
                    TextEditor(text: $input)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(4)
                }
                .frame(minWidth: 200)

                VStack(spacing: 0) {
                    OutputPane(title: "转义为 \\uXXXX →", content: escaped)
                    Divider()
                    OutputPane(title: "解析 \\uXXXX ←", content: unescaped)
                }
                .frame(minWidth: 200)
            }
        }
    }
}

// MARK: - HTML Entities

private struct HTMLEntitiesTool: View {
    @State private var input = ""

    private static let basicEntities: [(String, String)] = [
        ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"),
        ("\"", "&quot;"), ("'", "&#39;"),
    ]

    var encoded: String {
        var s = input
        // & must be first
        for (raw, entity) in HTMLEntitiesTool.basicEntities {
            s = s.replacingOccurrences(of: raw, with: entity)
        }
        return s
    }

    var decoded: String {
        var s = input
        for (raw, entity) in HTMLEntitiesTool.basicEntities.reversed() {
            s = s.replacingOccurrences(of: entity, with: raw)
        }
        // Numeric entities &#nnn; and &#xHH;
        let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        if let regex = regex {
            let nsString = s as NSString
            let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length)).reversed()
            var mutable = s
            for m in matches {
                let isHex = nsString.substring(with: m.range(at: 1)) == "x"
                let numStr = nsString.substring(with: m.range(at: 2))
                if let value = UInt32(numStr, radix: isHex ? 16 : 10),
                   let scalar = Unicode.Scalar(value) {
                    let replacement = String(Character(scalar))
                    if let range = Range(m.range, in: mutable) {
                        mutable.replaceSubrange(range, with: replacement)
                    }
                }
            }
            s = mutable
        }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HTML 实体编解码").font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    input = NSPasteboard.general.string(forType: .string) ?? ""
                } label: { Label("粘贴", systemImage: "doc.on.clipboard").font(.system(size: 11)) }
                .buttonStyle(.bordered).controlSize(.mini)
                Button { input = "" } label: { Image(systemName: "trash").font(.system(size: 11)) }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("输入").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }.padding(8)
                    TextEditor(text: $input)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(4)
                }
                .frame(minWidth: 200)

                VStack(spacing: 0) {
                    OutputPane(title: "HTML 编码 →", content: encoded)
                    Divider()
                    OutputPane(title: "HTML 解码 ←", content: decoded)
                }
                .frame(minWidth: 200)
            }
        }
    }
}
