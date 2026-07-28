<div align="center">

# Windows Ghost Device Cleanup

[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blueviolet.svg)](https://github.com/PowerShell/PowerShell)
[![XAML](https://img.shields.io/badge/UI-XAML%20%2F%20WPF-orange.svg)](https://docs.microsoft.com/dotnet/framework/wpf/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

</div>

- 本项目由Uwe Sieber 原版 [Device Cleanup Tool](https://www.uwe-sieber.de/misc_tools_e.html) 的改进与重新设计版本，采用现代 GUI，并增加对已配置 CPU 亲和性 / IRQ 绑定设备的自动保护——清晰标识且默认不勾选，避免误删。

<div align="center">

扫描并移除由先前连接硬件留下的 `幽灵设备` <br>
降低 IRQ 开销，减少输入延迟，让操作更顺滑 <br>
基于 Windows 内置工具原生运行。全程 `安全` 且 `非破坏性`

</div>

---

`幽灵设备`是指已不再连接的硬件在注册表中留下的残留条目。它们会静默占用 IRQ 资源，可能导致输入卡顿、USB 初始化变慢，以及驱动冲突。

## 📸 工具截图

![img](/screenshot/demo0.png)

<details>
<summary><b>点击此处展开</b></summary>

---

**扫描结果 — 检测到并列出幽灵设备，受保护设备予以保留**
> 所有检测到的设备都会显示其状态。幽灵设备（`幽灵`）默认已勾选，可随时移除。已配置 CPU 亲和性 / IRQ 绑定（`亲和性已配置`）的设备会单独列出，默认不勾选。

![img](/screenshot/demo1.png)

---

**确认移除 — 一键移除并弹出确认对话框**
> 删除前会弹出确认框，显示即将移除的设备数量。通过本工具执行的操作无法撤销——但如果重新连接硬件，设备会再次出现。

![img](/screenshot/demo2.png)

---

**移除之后 — 干净状态，仅保留受保护设备**
> 移除后，工具会自动重新扫描。幽灵数量降至 `0`，已移除数量更新为本次会话合计。仅保留 `亲和性已配置` 的设备，完整未动。

![img](/screenshot/demo3.png)
![img](/screenshot/demo4.png)

</details>

## 💡 为什么重要

- 每次插入外设——鼠标、键盘、USB 集线器、耳机——Windows 都会注册它。拔掉之后，条目仍会保留。久而久之，这些过时条目在注册表中静默堆积，占用 IRQ 资源，并在设备枚举过程中产生干扰。

- 设备清理会扫描系统中所有已注册设备，识别物理上已不存在的项，并一次性移除。结果是更干净的中断表、更快的 USB 初始化，以及更顺滑的输入——无需猜测。

- 所有更改仅限幽灵条目。活动设备，以及任何已配置 CPU 亲和性或 IRQ 绑定的设备，都不会被触碰。若已移除的设备重新连接，Windows 会将其作为新设备重新检测——不会永久丢失任何数据。

## ⬇️ 安装

```bash
git clone https://github.com/NeetheCheeBao/WinDeviceCleanup.git
```

```bash
gh repo clone NeetheCheeBao/WinDeviceCleanup
```

## 🚀 运行

**右键** `main.ps1` **使用 `PowerShell` 运行**

脚本会自动请求 `🛡️管理员权限`

> [!CAUTION]
> 若系统禁止运行 PowerShell 脚本，请先启用执行策略：
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

## 🌟 使用方法

1. 点击 `扫描系统` 工具会扫描 Windows 中注册的所有设备，包括已断开连接的设备
2. 查看列表,幽灵设备标记为`幽灵`，受保护设备标记为`亲和性已配置`
3. 选择要移除的设备（所有幽灵设备默认已勾选）
4. 点击`移除所选`并确认
5. 移除后工具会自动重新扫描，确认设备已消失

## 🔨 工具功能

| 功能 | 说明 |
|---|---|
| **幽灵设备扫描** | 检测所有状态为 `Unknown`（错误代码 45）的设备——硬件已不再连接 |
| **亲和性保护** | 自动保留任何已配置 CPU 亲和性 / IRQ 绑定的设备 |
| **安全移除** | 通过最多 5 种回退方法移除幽灵条目 — `Remove-PnpDevice`、`pnputil`、SetupAPI、`reg.exe`、`devcon` |

## 📋 设备标签

| 标签 | 含义 |
|---|---|
| **`幽灵`** | 幽灵设备：曾连接，现已不存在。可安全移除。 |
| **`亲和性已配置`** | 设备已配置 IRQ / CPU 亲和性绑定。默认受保护，可手动移除。 |

> [!IMPORTANT]
> 标记为 `亲和性已配置` 的设备默认不勾选。移除它们会删除你的 IRQ 亲和性配置。请仅在有意为之的情况下操作。

## ✅ 收益

收益随移除设备数量而放大。在曾连接大量外设的系统上效果最明显。

| 改进 | 详情 |
|---|---|
| **更低输入延迟** | 更少的幽灵 IRQ 条目争抢资源 |
| **无 IRQ 冲突** | 活动设备的中断路由更干净 |
| **更快 USB 初始化** | Windows 不再枚举过时的设备条目 |
| **更快启动** | 启动时设备枚举减少 |
| **更干净的注册表** | 移除 `HKLM\SYSTEM\CurrentControlSet\Enum` 下的死条目 |

## 🛠️ 移除方法链

工具按以下顺序尝试移除，在首次成功时停止：

1. `Remove-PnpDevice` — 原生 PowerShell cmdlet
2. `pnputil.exe /remove-device` — Windows 内置 PnP 工具
3. **SetupAPI** `SetupDiRemoveDevice` — 直接 Win32 API 调用，绕过 PnP 管理器锁定
4. `reg.exe delete` — 强制删除注册表键
5. `devcon.exe remove` — 若系统或脚本目录中存在