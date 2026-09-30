<div align="center">

# Windows Ghost Device Cleanup

[![Platform](https://img.shields.io/badge/Platform-Windows_10%2F11-blue.svg)](https://www.microsoft.com/windows)
[![Runtime](https://img.shields.io/badge/.NET_Framework-4.8-blueviolet.svg)](https://dotnet.microsoft.com/download/dotnet-framework)
[![Language](https://img.shields.io/badge/Language-C%23-239120.svg)](https://learn.microsoft.com/dotnet/csharp/)
[![UI](https://img.shields.io/badge/UI-WPF-purple.svg)](https://learn.microsoft.com/dotnet/desktop/wpf/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 本项目由 Uwe Sieber 原版 [Device Cleanup Tool](https://www.uwe-sieber.de/misc_tools_e.html) 的改进与重新设计版本，采用现代 GUI 重制

#### 扫描并移除由先前连接硬件留下的 `幽灵设备`
#### 降低 IRQ 开销，减少输入延迟，让操作更顺滑
#### 基于 Windows 内置工具原生运行。全程 `安全` 且 `非破坏性`

</div>

> `幽灵设备`是指已不再连接的硬件在注册表中留下的残留条目。它们会静默占用 IRQ 资源，可能导致输入卡顿、USB 初始化变慢，以及驱动冲突

## 📸 工具截图

![img](/screenshot/demo1.png)

<details>
<summary><b>点击此处展开</b></summary>

---

**扫描结果 — 检测到并列出幽灵设备，受保护设备予以保留**
> 所有检测到的设备都会显示其状态。幽灵设备（`幽灵`）默认已勾选，可随时移除。已配置 CPU 亲和性 / IRQ 绑定（`亲和性已配置`）的设备会单独列出，默认不勾选

![img](/screenshot/demo2.png)

---

**确认移除 — 一键移除并弹出确认对话框**
> 删除前会弹出确认框，显示即将移除的设备数量。通过本工具执行的操作无法撤销——但如果重新连接硬件，设备会再次出现

![img](/screenshot/demo3.png)

---

**移除之后 — 干净状态，仅保留受保护设备**
> 移除后，工具会自动重新扫描。幽灵数量降至 `0`，已移除数量更新为本次会话合计。仅保留 `亲和性已配置` 的设备，完整未动

![img](/screenshot/demo4.png)

</details>

## 💡 为什么重要

- 每次插入外设（鼠标、键盘、USB 集线器、耳机）Windows 都会注册它。拔掉之后，注册条目仍会保留。久而久之，这些过时条目在注册表中静默堆积，占用 IRQ 资源，并在设备枚举过程中产生干扰

- 本工具会扫描系统中所有已注册设备，识别物理上已不存在的项，并一次性移除

- 所有更改仅限幽灵条目。活动设备，以及任何已配置`CPU亲和性`或`IRQ 绑定`的设备，都不受影响。若已移除的设备重新连接，Windows会将其作为新设备重新注册

## ⬇️ 下载使用

前往 [Releases](https://github.com/NeetheCheeBao/WinDeviceCleanup/releases) 下载最新版

## 🚀 运行

启动时可能会弹出 UAC 提示，确认后自动以管理员身份运行

### 环境支持

| 项目 | 要求 |
|---|---|
| **系统** | Windows 10 / 11（64 位或 32 位均可） |
| **.NET Framework** | 4.8（Windows 10 1903 起系统自带） |
| **PowerShell** | 5.1（Windows 10/11 系统自带） |

## 🌟 使用方法

1. 点击 `扫描系统`（或按 `F5`）工具会扫描系统中注册的所有设备，包括已断开连接的设备
2. 查看列表：幽灵设备标记为 `幽灵`，受保护设备标记为 `亲和性已配置`
3. 勾选要移除的设备（所有幽灵设备默认已勾选）
4. 点击 `移除所选` 并确认
5. 移除后工具会自动重新扫描，确认设备已消失

## 🔨 工具功能

| 功能 | 说明 |
|---|---|
| **幽灵设备扫描** | 检测所有状态为 `Unknown`（`CM_PROB_PHANTOM`，错误代码 45）的设备 |
| **亲和性保护** | 自动保留任何已配置 CPU 亲和性 / IRQ 绑定的设备 |
| **双通路扫描** | 优先使用 PnP 模块；该通路失效时自动切换到 `pnputil`，绕过 WMI |
| **分级移除** | 三级回退移除，任一级成功即停止（见下文） |
| **运行日志** | 每次启动在 `WDC_log\` 下新建日志，记录扫描通路与逐项移除结果 |
| **界面不冻结** | 扫描与移除在后台线程执行，界面全程可响应 |

## 📋 设备标签

| 标签 | 含义 |
|---|---|
| **`幽灵`** | 幽灵设备：曾经存在连接的设备，现已不存在。可安全移除 |
| **`亲和性已配置`** | 设备已配置 IRQ / CPU 亲和性绑定。默认受保护，可手动移除 |

> [!IMPORTANT]
> 标记为 `亲和性已配置` 的设备默认不勾选，也不会被「全选」勾中。移除它们会删除你的 IRQ 亲和性配置，请仅在有意为之的情况下操作

## ✅ 收益

收益随移除设备数量而放大。在曾连接大量外设的系统上效果最明显

| 改进 | 详情 |
|---|---|
| **更低输入延迟** | 更少的幽灵 IRQ 条目争抢资源 |
| **无 IRQ 冲突** | 活动设备的中断路由更干净 |
| **更快 USB 初始化** | Windows 不再枚举过时的设备条目 |
| **更快启动** | 启动时设备枚举减少 |
| **更干净的注册表** | 移除 `HKLM\SYSTEM\CurrentControlSet\Enum` 下的死条目 |

## 🛠️ 移除方法链

工具按以下顺序尝试，**首次成功即停止**：

| 级别 | 方法 | 说明 |
|---|---|---|
| 1 | `Remove-PnpDevice` | PnP 模块命令。**Windows 11 的 PnpDevice 模块并不提供此命令**，因此会自动跳过 |
| 2 | `pnputil.exe /remove-device` | PnP 管理器命令行。**实际生效的主力方法** |
| 3 | 删除注册表键 | 最后兜底，绕过 PnP 管理器。仅在 1、2 级均失败时使用 |

> [!WARNING]
> 第 3 级直接删除 `HKLM\SYSTEM\CurrentControlSet\Enum\<实例ID>`，**绕过 PnP 管理器**。这是最后的兜底手段，工具不会在日志中特别标注使用了哪一级，若需确认请查看 `WDC_log\` 下的日志。

## 🔍 扫描通路

扫描优先使用 `Get-PnpDevice`（PnP 模块）。该通路不可用时，自动切换到 `pnputil /enum-devices /disconnected`——后者直接与 PnP 管理器通信，不经过 WMI。

## 📄 日志

- 每次启动在 exe 同目录的 `WDC_log\` 下新建一个日志文件：
日志记录内容包括：程序版本与权限状态、扫描使用的通路与设备数量、每个设备的移除结果、PowerShell 错误详情、会话汇总

## 🔧 从源码构建

1. 克隆仓库

```bash
git clone https://github.com/NeetheCheeBao/WinDeviceCleanup.git
```

```bash
gh repo clone NeetheCheeBao/WinDeviceCleanup
```

2. 一键编译

```bash
.\build.bat
```

### 源码结构

```text
Project
├─ build.bat                    一键编译脚本
├─ main.sln
├─ README.md
├─ LICENSE
├─ .gitignore
├─ assets\
│  └─ icon.ico
├─ screenshot\
│  ├─ demo1.png
│  ├─ demo2.png
│  ├─ demo3.png
│  └─ demo4.png
└─ src\
   ├─ WinDeviceCleanup.csproj   项目文件
   ├─ App\                      界面层
   │  ├─ MainWindow.xaml        界面定义
   │  ├─ MainWindow.xaml.cs     界面逻辑
   │  ├─ AppState.cs            控件引用与会话状态
   │  └─ app.manifest           请求管理员权限
   └─ Core\                     逻辑层（不引用任何界面代码）
      ├─ Program.cs             程序入口
      ├─ Logger.cs              运行日志
      ├─ Diagnostics.cs         异常展开工具
      ├─ Probe.cs               只读探测
      ├─ Models\
      │  └─ DeviceItem.cs       设备数据模型
      └─ Services\
         ├─ DeviceService.cs    业务流程编排
         └─ PowerShellBackend.cs 设备查询与移除
```


## ⚖️ 许可证

本项目采用 MIT 许可证 - 详情请参阅 [LICENSE](LICENSE) 文件
