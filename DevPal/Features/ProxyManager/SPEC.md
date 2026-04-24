# 网络代理管理 — 功能需求文档

> 模块路径：`Features/ProxyManager/`  
> 目标：可视化查看系统代理状态，一键关闭/重置代理，解决代理工具退出后网络不可用的问题

---

## 一、功能定位

开发者常用 ClashX、Surge、V2Ray、Shadowsocks 等代理工具。这些工具通过修改 macOS 系统网络代理设置来工作，但有时异常退出或关闭后，**系统代理设置残留**（HTTP/HTTPS/SOCKS 代理仍指向 127.0.0.1:xxxx），导致浏览器和终端无法访问网络。

本模块提供：
- 当前系统代理状态的可视化展示
- 一键关闭所有代理（恢复直连）
- 快速诊断网络连通性

---

## 二、核心功能

### 2.1 代理状态总览

读取当前活跃网络接口（Wi-Fi / Ethernet）的所有代理设置，以卡片形式展示：

| 代理类型 | 读取命令 | 关键信息 |
|---|---|---|
| HTTP 代理 | `networksetup -getwebproxy <service>` | 开关状态、服务器、端口 |
| HTTPS 代理 | `networksetup -getsecurewebproxy <service>` | 开关状态、服务器、端口 |
| SOCKS 代理 | `networksetup -getsocksfirewallproxy <service>` | 开关状态、服务器、端口 |
| 自动代理 (PAC) | `networksetup -getautoproxyurl <service>` | 开关状态、PAC URL |
| 自动发现 (WPAD) | `networksetup -getproxyautodiscovery <service>` | 开关状态 |

每个代理类型显示：
- 🟢 开启（显示服务器:端口）/ 🔴 关闭
- 如果开启且指向 `127.0.0.1` 或 `localhost`，标注 **"本地代理"**
- 如果开启但代理端口无响应，标注 **⚠️ 代理不可达**（这就是断网的原因）

### 2.2 网络接口选择

- 自动检测当前活跃的网络接口：
  ```bash
  networksetup -listallnetworkservices
  ```
- 常见接口：`Wi-Fi`、`Ethernet`、`USB 10/100/1000 LAN`
- 默认选中当前联网的接口
- 支持下拉切换查看不同接口的代理

### 2.3 一键操作

#### 「关闭所有代理」（核心功能）
执行：
```bash
networksetup -setwebproxystate <service> off
networksetup -setsecurewebproxystate <service> off
networksetup -setsocksfirewallproxystate <service> off
networksetup -setautoproxystate <service> off
networksetup -setproxyautodiscovery <service> off
```
操作后自动刷新状态面板。

#### 「恢复默认」
将所有代理设为关闭，等同于全新系统的状态（所有代理 off，无残留配置）。

### 2.4 网络连通性快速诊断

在代理状态下方，提供一个小型诊断面板：
- 点击「检测网络」，依次检测：
  - DNS 解析：`nslookup www.apple.com`
  - 国内连通：`curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://www.baidu.com`
  - 国外连通：`curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://www.google.com`
- 每项显示 ✅ / ❌ + 耗时
- 如果国内也不通 + 代理开启 → 明确提示 **"系统代理开启但代理服务不可用，建议关闭代理"**

### 2.5 环境变量代理提示

检测 shell 环境变量中的代理设置：
```bash
echo $http_proxy $https_proxy $all_proxy
```
如果有残留的环境变量代理，显示提示："终端代理环境变量仍有设置，可能需要在 ~/.zshrc 中清理"

---

## 三、UI 设计

```
┌─────────────────────────────────────────────────┐
│  网络代理管理                                     │
├─────────────────────────────────────────────────┤
│                                                 │
│  网络接口: [Wi-Fi ▼]           [刷新] [检测网络] │
│                                                 │
│  ┌─ 代理状态 ──────────────────────────────┐    │
│  │                                         │    │
│  │  HTTP 代理     🟢 开启  127.0.0.1:7890  │    │
│  │                ⚠️ 代理不可达             │    │
│  │                                         │    │
│  │  HTTPS 代理    🟢 开启  127.0.0.1:7890  │    │
│  │                ⚠️ 代理不可达             │    │
│  │                                         │    │
│  │  SOCKS 代理    🔴 关闭                   │    │
│  │                                         │    │
│  │  自动代理(PAC)  🔴 关闭                   │    │
│  │                                         │    │
│  │  自动发现       🔴 关闭                   │    │
│  │                                         │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  ⚠️ 检测到代理已开启但服务不可达，可能导致断网     │
│                                                 │
│  ┌──────────────┐  ┌──────────────┐            │
│  │ 🔴 关闭所有代理 │  │ ↺ 恢复默认    │            │
│  └──────────────┘  └──────────────┘            │
│                                                 │
│  ┌─ 网络诊断 ──────────────────────────────┐    │
│  │  DNS 解析      ✅ 正常  12ms            │    │
│  │  国内连通      ❌ 不通                   │    │
│  │  国外连通      ❌ 不通                   │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 四、技术实现要点

### 4.1 核心类

```
ProxyStatus         — 单个代理类型的状态模型（类型、开关、服务器、端口、可达性）
NetworkService      — 网络接口模型（名称、是否活跃）
ProxyManager        — 读取/设置系统代理（调用 networksetup）
NetworkDiagnostics  — 网络连通性检测
ProxyViewModel      — 视图状态管理
```

### 4.2 权限说明

- `networksetup -getXXXproxy` 不需要 sudo
- `networksetup -setXXXproxystate` **不需要 sudo**（修改当前用户的网络设置）
- 但某些企业管理的 Mac 可能需要管理员权限，此时提示用户

### 4.3 自动检测活跃接口

```bash
# 获取默认路由的网络接口
route -n get default 2>/dev/null | grep interface
# 映射到 networksetup 的 service name
networksetup -listallnetworkservices
```

---

## 五、MVP 范围

1. ✅ 代理状态总览（HTTP/HTTPS/SOCKS/PAC/自动发现）
2. ✅ 一键关闭所有代理
3. ✅ 网络接口自动检测与切换
4. ✅ 网络连通性快速诊断
5. ✅ 代理不可达警告

后续版本：
- 代理配置快照保存/恢复（切换不同代理方案）
- 终端环境变量代理检测与清理引导
- 菜单栏快捷操作
