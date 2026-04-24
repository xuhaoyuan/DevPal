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

### 👁 隐藏文件切换
- 一键全局显示/隐藏 macOS 隐藏文件
- 常用隐藏目录快捷入口（~/.ssh、~/.gitconfig、~/.zshrc 等）
- 拖拽文件管理单文件隐藏属性（chflags）

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
├── Core/                   → 通用工具（Shell、文件权限）
├── Features/
│   ├── SSH/                → SSH 密钥与配置管理
│   └── HiddenFiles/        → 隐藏文件显示切换
└── project.yml             → XcodeGen 配置
```

## License

MIT
