# 隐藏文件切换 — 功能需求文档

> 模块路径：`Features/HiddenFiles/`  
> 目标：一键切换 macOS Finder 隐藏文件的显示状态，附带常用隐藏文件快捷入口

---

## 一、功能定位

macOS 默认隐藏以 `.` 开头的文件（dotfiles），开发者经常需要在「显示」和「隐藏」之间来回切换。系统原生方式是快捷键 `Cmd+Shift+.`（仅对当前 Finder 窗口生效）或终端命令 `defaults write`（全局生效但需要重启 Finder）。本模块提供一个可视化的开关，一键全局切换，无需记忆命令。

---

## 二、核心功能

### 2.1 全局显示/隐藏切换

- 界面上有一个醒目的开关（Toggle Switch）
- 读取当前系统状态：
  ```bash
  defaults read com.apple.finder AppleShowAllFiles
  ```
  - 返回 `1` 或 `YES` → 当前为「显示隐藏文件」
  - 返回 `0`、`NO` 或命令报错（未设置过）→ 当前为「隐藏」
- 切换时执行：
  ```bash
  # 显示隐藏文件
  defaults write com.apple.finder AppleShowAllFiles -bool true
  killall Finder

  # 隐藏隐藏文件
  defaults write com.apple.finder AppleShowAllFiles -bool false
  killall Finder
  ```
- 切换后自动重启 Finder 使设置生效
- 界面上显示当前状态文字："隐藏文件当前 **已显示** / **已隐藏**"

### 2.2 状态实时同步

- 应用启动时读取当前系统设置
- 监听系统偏好变化（定时轮询 `defaults read`，间隔 3 秒）
- 如果用户通过终端或快捷键改变了状态，界面自动同步

### 2.3 常用隐藏文件/目录快捷入口

提供一组常用隐藏目录的快捷按钮，点击直接在 Finder 中打开：

| 路径 | 说明 |
|---|---|
| `~/.ssh/` | SSH 密钥与配置 |
| `~/.gitconfig` | Git 全局配置 |
| `~/.zshrc` | Zsh 配置 |
| `~/.config/` | 各种工具的配置目录 |
| `~/Library/` | 用户 Library（系统默认隐藏） |
| `/etc/hosts` | Hosts 文件 |

- 每个入口显示：路径 + 说明 + 是否存在（不存在时灰色标注）
- 点击 → `NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)`
- 长按/右键 → 「在终端中打开」（`open -a Terminal <path>`）

### 2.4 单文件/目录的隐藏属性管理

- 拖拽文件/目录到窗口区域
- 读取该文件的隐藏属性：
  ```bash
  ls -lO <path>  # 看是否有 hidden flag
  ```
  或通过 `chflags` 检查
- 显示：文件名 + 当前隐藏状态 + 切换按钮
- 切换命令：
  ```bash
  chflags hidden <path>    # 隐藏
  chflags nohidden <path>  # 取消隐藏
  ```

---

## 三、UI 设计

```
┌─────────────────────────────────────────────────┐
│  隐藏文件管理                                     │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │                                         │    │
│  │     🔓 隐藏文件当前：已隐藏              │    │
│  │                                         │    │
│  │         ┌──────────────┐                │    │
│  │         │  ● 显示全部   │                │    │
│  │         └──────────────┘                │    │
│  │                                         │    │
│  │     切换后将重启 Finder 使设置生效        │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  常用隐藏目录                                    │
│  ┌─────────────────────────────────────────┐    │
│  │  📁 ~/.ssh/          SSH 密钥      [打开] │   │
│  │  📄 ~/.gitconfig     Git 配置      [打开] │   │
│  │  📄 ~/.zshrc         Zsh 配置      [打开] │   │
│  │  📁 ~/.config/       工具配置      [打开] │   │
│  │  📁 ~/Library/       用户 Library  [打开] │   │
│  │  📄 /etc/hosts       Hosts 文件    [打开] │   │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  单文件隐藏管理                                   │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐    │
│  │    拖拽文件到此处，管理隐藏属性           │    │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 四、技术实现要点

### 4.1 核心类设计

```
FinderSettings       — 读写 Finder 的 AppleShowAllFiles 设置
HiddenFileManager    — 单文件 chflags 隐藏属性管理
HiddenFilesViewModel — 视图状态管理（当前开关状态、快捷目录列表、拖拽文件）
```

### 4.2 Finder 重启策略

- `killall Finder` 会导致所有 Finder 窗口关闭后重新打开
- 切换前给用户提示："将重启 Finder，当前窗口会短暂闪动"
- 切换后 0.5 秒延迟再读取状态，确保新设置已生效

### 4.3 权限

- `defaults write` 和 `killall Finder` 不需要 sudo
- `chflags` 对用户自己的文件不需要 sudo，系统文件需要（暂不支持）

---

## 五、MVP 范围

1. ✅ 全局显示/隐藏切换（大开关 + killall Finder）
2. ✅ 当前状态实时读取与显示
3. ✅ 常用隐藏目录快捷入口
4. ✅ 单文件拖拽查看/切换隐藏属性

后续版本：
- 菜单栏常驻图标（StatusBarItem），一键切换
- 快捷键绑定
- 切换历史记录
