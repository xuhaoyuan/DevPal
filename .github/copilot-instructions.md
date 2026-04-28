# DevPal — Copilot 编码规范

Native macOS developer toolbox. Swift + SwiftUI, macOS 14.0+, no App Sandbox, distributed as DMG.
Build with XcodeGen: `xcodegen generate` regenerates `.xcodeproj` from `project.yml`.

---

## 项目结构

```
DevPal/
├── App/                      # DevPalApp.swift, ContentView.swift, UpdaterViewModel.swift
├── Core/                     # Shell.swift, PersistentSplitView.swift, ReadOnlyTextView.swift, FilePermissions.swift
└── Features/
    └── {FeatureName}/
        ├── Models/            # 纯数据 struct/enum — 无 I/O
        ├── Views/             # SwiftUI 视图 + XxxViewModel.swift
        └── Managers/          # 系统访问类 (static .shared 单例)
```

每个功能模块自包含，新功能必须遵循此目录结构。

---

## 命名规范

- 视图: `XxxMainView.swift` (功能入口), `XxxView.swift`, `XxxViewModel.swift`
- 模型: `XxxModels.swift` 或 `XxxModel.swift`
- 管理器: `XxxManager.swift`
- Tab 枚举: `Tab` (嵌套在 View 内) 或 `XxxTab` (文件作用域) — rawValue 使用中文名
- 模型类型: `struct XxxModel: Identifiable, Hashable`

---

## 功能注册 (ContentView)

在 `Feature` 枚举中添加 case，在 detail switch 中添加路由：

```swift
enum Feature: String, CaseIterable, Identifiable {
    case myFeature = "功能名称"
    var id: String { rawValue }
    var icon: String { "sf.symbol" }
    var description: String { "简短说明" }
}

// toolCases 排除 .settings
static var toolCases: [Feature] { allCases.filter { $0 != .settings } }
```

侧边栏使用 `List(selection:)` + `.listStyle(.sidebar)` + `.onMove`（顺序持久化到 `UserDefaults["sidebarOrder"]`）。Settings 固定在底部。窗口默认大小: 900×620。

---

## Tab 枚举模板

每个有子页面的功能都用此模式：

```swift
enum Tab: String, CaseIterable {
    case first = "标签名"

    var icon: String {
        switch self { case .first: return "sf.symbol.name" }
    }
    var subtitle: String {
        switch self { case .first: return "简短描述" }
    }
}
@State private var selectedTab: Tab = .first
```

---

## PersistentSplitView 模板

所有有侧边栏的功能视图都用此组件，宽度按 `id` 持久化：

```swift
PersistentSplitView(id: "featureName", minWidth: 120, maxWidth: 220, defaultWidth: 150) {
    VStack(spacing: 2) {
        ForEach(Tab.allCases, id: \.self) { tab in
            sidebarButton(tab)
        }
        Spacer()
    }
    .padding(8)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
} content: {
    Group {
        switch selectedTab {
        case .first: FirstTabView(viewModel: viewModel)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

---

## 侧边栏按钮模板 (严格遵循，不可偏离)

```swift
Button {
    selectedTab = tab
} label: {
    HStack(spacing: 8) {
        Image(systemName: tab.icon)
            .font(.system(size: 12))
            .frame(width: 18)
        VStack(alignment: .leading, spacing: 1) {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: .medium))
            Text(tab.subtitle)
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
            .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
    )
    .foregroundColor(selectedTab == tab ? .accentColor : .primary)
}
.buttonStyle(.plain)
```

规则: `.contentShape(Rectangle())` 必须存在以确保整行可点击; 必须 `.buttonStyle(.plain)`。

---

## Shell.run() 模板

```swift
// 便捷方法 — 通过 /bin/zsh -c "..." 执行
// Result: .stdout, .stderr, .exitCode, .succeeded (exitCode == 0)

// 忽略错误:
let result = try? await Shell.run("some command")
let output = result?.stdout ?? ""

// 带错误处理:
let result = try await Shell.run("ssh-keygen -t ed25519 -f \(path) -N ''", timeout: 60)
guard result.succeeded else { throw MyError.failed(result.stderr) }

// 按钮中调用 (同步 → 异步):
Button("刷新") { Task { await viewModel.refresh() } }
```

默认超时: 30s。直接二进制调用用 `Shell.execute(_:arguments:timeout:)`。

---

## ViewModel 模板

```swift
@MainActor
class XxxViewModel: ObservableObject {
    @Published var items: [XxxModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let manager = XxxManager.shared

    init() { Task { await refresh() } }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await manager.loadItems()
        } catch {
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
    }

    func clearMessages() { errorMessage = nil; successMessage = nil }
}
```

- 必须 `@MainActor class` + `ObservableObject`
- 在拥有视图中用 `@StateObject`，传给子视图用 `viewModel:` 参数
- `init()` 通过 `Task { await refresh() }` 触发初始加载

---

## Manager 模板

```swift
class XxxManager {
    static let shared = XxxManager()

    func loadItems() async throws -> [XxxModel] { /* Shell 或 FileManager */ }
    func saveItem(_ item: XxxModel) throws { /* FileManager */ }
}
```

普通 `class`（非 actor），`static let shared` 单例。异步操作用 async throws，文件写入用 throws。

---

## Model 模板

```swift
struct XxxModel: Identifiable, Hashable {
    let id: UUID
    var field: String
    // 计算属性可以; 不可有 I/O
}
```

---

## ReadOnlyTextView

大文本只读显示用此组件 — 避免 SwiftUI `Text` 布局卡顿：

```swift
ReadOnlyTextView(text: someString)
    .frame(maxWidth: .infinity, maxHeight: .infinity)

// 自定义字体:
ReadOnlyTextView(text: content, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
```

默认: 等宽 12pt，可滚动，可选中文本，支持查找栏。

---

## 消息栏模板

```swift
if let error = viewModel.errorMessage { messageBar(text: error, isError: true) }
if let success = viewModel.successMessage { messageBar(text: success, isError: false) }

private func messageBar(text: String, isError: Bool) -> some View {
    HStack {
        Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
            .foregroundColor(isError ? .red : .green)
        Text(text).font(.system(size: 12))
        Spacer()
        Button { viewModel.clearMessages() } label: {
            Image(systemName: "xmark").font(.system(size: 10))
        }.buttonStyle(.plain)
    }
    .padding(.horizontal, 12).padding(.vertical, 6)
    .background(isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
}
```

---

## 布局约定

```swift
VStack(spacing: 0) {
    // 警告 / 错误 / 成功消息栏
    // 工具栏: HStack + .padding(12)
    Divider()
    // 内容区
    Divider()
    // 状态栏: HStack, 10–11pt 文本
}
.task { await viewModel.refresh() }
```

- 工具栏: `HStack` + `.padding(12)`
- 操作按钮: `.buttonStyle(.bordered)` + `.controlSize(.small)`
- 空状态: 居中 `VStack` + 40pt SF Symbol + `.foregroundColor(.secondary)`
- 加载状态: `ProgressView("加载中...")` 在两个 `Spacer()` 之间

---

## 样式常量

| 用途 | 值 |
|---|---|
| 选中背景 | `Color.accentColor.opacity(0.15)` |
| 侧边栏背景 | `Color(nsColor: .controlBackgroundColor).opacity(0.3)` |
| 搜索框背景 | `Color(nsColor: .controlBackgroundColor)` |
| 错误栏 | `Color.red.opacity(0.08)` |
| 成功栏 | `Color.green.opacity(0.08)` |
| 警告栏 | `Color.orange.opacity(0.1)` |
| 圆角半径 | `6` |

---

## 字体规格

| 用途 | 大小 | 字重 |
|---|---|---|
| 侧边栏项目名 | 12pt | `.medium` |
| 侧边栏副标题 | 9pt | regular |
| 正文 / 表格行 | 11–12pt | regular |
| 等宽内容 | 11–12pt | monospaced |
| 状态栏 | 10–11pt | regular |

---

## UI 语言与图标

- 所有 UI 文本使用简体中文
- 所有图标使用 SF Symbols — 不用自定义图片资源
- 强调色使用系统强调色（不硬编码蓝色）

---

## 平台与构建

| 设置 | 值 |
|---|---|
| 语言 | Swift 5.9 |
| 部署目标 | macOS 14.0 |
| App Sandbox | 已禁用 |
| 分发方式 | DMG (非 App Store) |
| 构建系统 | XcodeGen (`project.yml`) |
| 自动更新 | Sparkle 2.6.0 |
| Bundle ID | `com.devpal.app` |

可自由使用 macOS 专有 API（`NSPasteboard`, `NSCursor`, `NSTextView` 等）。不使用 UIKit，不支持 iOS。

---

## 依赖

- **Sparkle** 2.6.0 — 自动更新。通过 `UpdaterViewModel`（`ObservableObject`，封装 `SPUStandardUpdaterController`）集成，在 `SettingsView` 中通过 `@EnvironmentObject` 访问。
- 无其他第三方依赖。尽量不添加新依赖。
