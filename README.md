# DevPal

macOS 开发者工具箱 — 将常用系统操作整合到一个轻量原生应用中。

> Swift + SwiftUI · macOS 14.0+ · 非沙盒应用

## 功能模块

### 🔑 SSH 管理
- 扫描、生成、删除、重命名 SSH 密钥
- 可视化编辑 `~/.ssh/config`（表单 + 实时预览）
- 连通性测试（单个 / 批量）
- 自动备份与恢复
- 文件权限检查与一键修复

### � 包管理
- 自动检测本地已安装的包管理器（Homebrew、npm、yarn、pnpm、pip3、pipx、conda、gem、cargo、go、composer、CocoaPods）
- 浏览所有已安装包，支持搜索、排序、筛选（Homebrew Formula/Cask）
- 查看包详情（描述、主页、许可证、依赖、原始信息）
- 检查更新（单个包 / 全部包）
- 安装新包（搜索 / 直接输入）、卸载、升级
- 安装/卸载包管理器本身
- 健康检查、磁盘占用、导出包列表
- npm/brew 使用 JSON 解析获取丰富详情

### 👁 隐藏文件切换
- 一键全局显示/隐藏 macOS 隐藏文件
- 常用隐藏目录快捷入口（~/.ssh、~/.gitconfig、~/.zshrc 等）
- 拖拽文件管理单文件隐藏属性（chflags）

### 🌐 网络代理管理
- 查看系统代理状态（HTTP/HTTPS/SOCKS/PAC）
- 一键关闭所有代理 / 恢复默认
- 代理服务不可达警告（解决代理工具退出后断网）
- 网络连通性快速诊断（DNS / 国内 / 国外）

### 🔌 端口管理
- 查看系统端口占用情况
- 按端口号/进程名搜索
- 一键杀进程

### 🔧 环境变量
- 查看当前 Shell 环境变量
- 查看/编辑 Profile 文件（~/.zshrc 等）

### 📝 JSON 工具
- JSON 格式化 / 压缩 / 校验
- 语法高亮显示

### 🔐 编解码工具
- Base64 编解码
- URL 编解码
- JWT 解析
- 多种 Hash 计算

### ⚙️ 设置
- Sparkle 自动更新
- 版本信息

## 构建

需要安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
```

生成 Xcode 项目并打开：

```bash
cd DevPal
xcodegen generate
open DevPal.xcodeproj
```

## 项目结构

```
DevPal/
├── App/                    → 应用入口 + 侧边栏导航
├── Core/                   → 通用工具（Shell、文件权限、分栏视图）
├── Features/
│   ├── SSH/                → SSH 密钥与配置管理
│   ├── PackageManager/     → 包管理器（12 种包管理器支持）
│   ├── HiddenFiles/        → 隐藏文件显示切换
│   └── ProxyManager/       → 网络代理管理
└── project.yml             → XcodeGen 配置
```

## License

MIT
