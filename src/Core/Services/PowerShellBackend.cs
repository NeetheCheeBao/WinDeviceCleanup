using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using WdcShell.Core;

namespace WdcShell.Services
{
    /// <summary>
    /// 设备后端。扫描优先走 PnpDevice 模块，该通路不可用时回退到 pnputil.exe
    /// （PnP 管理器命令行，不经过 WMI）。两条通路产出的数据结构一致。
    /// </summary>
    public static class PowerShellBackend
    {
        /// <summary>上一次扫描实际使用的通路，仅用于日志。</summary>
        public static string LastScanChannel = "";

        /// <summary>枚举幽灵设备（PnP 状态为 Unknown 的条目）。</summary>
        public static List<DeviceItem> Scan()
        {
            List<DeviceItem> list;

            if (TryScanByPnpDevice(out list))
            {
                LastScanChannel = "Get-PnpDevice";
                Logger.Write("扫描通路  : Get-PnpDevice, " + list.Count + " 个幽灵设备");
                return list;
            }

            Logger.Write("Get-PnpDevice 通路不可用，切换到 pnputil");
            if (TryScanByPnputil(out list))
            {
                LastScanChannel = "pnputil";
                Logger.Write("扫描通路  : pnputil, " + list.Count + " 个幽灵设备");
                return list;
            }

            LastScanChannel = "全部失败";
            throw new Exception("两条查询通路均失败：Get-PnpDevice 与 pnputil");
        }

        static bool TryScanByPnpDevice(out List<DeviceItem> devices)
        {
            devices = new List<DeviceItem>();

            using (var ps = PowerShell.Create())
            {
                ps.AddScript(ScanByPnpDeviceScript);

                Collection<PSObject> output;
                try
                {
                    output = ps.Invoke();
                }
                catch (Exception ex)
                {
                    // 系统中没有幽灵设备时，Get-PnpDevice -PresentOnly:$false 会抛出
                    // ActionPreferenceStopException（消息随系统语言变化）。
                    // 这是正常状态而非故障，必须按"0 个设备"处理，
                    // 否则移除完最后一个设备后扫描会一直失败。
                    if (IsEmptyResultError(ps, ex))
                    {
                        Logger.Write("Get-PnpDevice 未找到任何幽灵设备（正常状态）");
                        devices.Clear();
                        return true;
                    }

                    Logger.Error("Get-PnpDevice 扫描通路", ex);
                    devices.Clear();
                    return false;
                }

                if (output != null)
                {
                    foreach (var o in output)
                    {
                        var item = ParseLine(o == null ? null : o.ToString());
                        if (item != null) devices.Add(item);
                    }
                }

                return true;
            }
        }

        static bool TryScanByPnputil(out List<DeviceItem> devices)
        {
            devices = new List<DeviceItem>();

            try
            {
                using (var ps = PowerShell.Create())
                {
                    ps.AddScript(ScanByPnputilScript);
                    var output = ps.Invoke();

                    if (ps.HadErrors)
                    {
                        foreach (ErrorRecord e in ps.Streams.Error)
                            Logger.Write("    pnputil 错误: " + Diagnostics.Describe(e));
                        return false;
                    }

                    if (output != null)
                    {
                        foreach (var o in output)
                        {
                            var item = ParseLine(o == null ? null : o.ToString());
                            if (item != null) devices.Add(item);
                        }
                    }

                    return true;
                }
            }
            catch (Exception ex)
            {
                Logger.Error("pnputil 扫描通路", ex);
                devices.Clear();
                return false;
            }
        }

        static DeviceItem ParseLine(string line)
        {
            if (string.IsNullOrEmpty(line)) return null;

            string[] parts = line.Split('\t');
            if (parts.Length < 3) return null;

            return new DeviceItem
            {
                Name = parts[0],
                InstanceId = parts[1],
                IsProtected = parts[2] == "1"
            };
        }

        /// <summary>
        /// 判断异常是否表示「查询结果为空」。
        /// 依据必须是语言无关的特征（异常类型 + ErrorActionPreference 变量名），
        /// 因为此时 ps.Streams.Error 为空，且消息文本随系统语言变化。
        /// </summary>
        static bool IsEmptyResultError(PowerShell ps, Exception ex)
        {
            try
            {
                foreach (ErrorRecord e in ps.Streams.Error)
                    if (IsEmptyResultRecord(e)) return true;
            }
            catch { }

            for (Exception cur = ex; cur != null; cur = cur.InnerException)
            {
                string msg = cur.Message;
                if (string.IsNullOrEmpty(msg)) continue;

                if (msg.IndexOf("NotFound", StringComparison.OrdinalIgnoreCase) >= 0) return true;
                if (msg.IndexOf("CimJobException", StringComparison.OrdinalIgnoreCase) >= 0) return true;

                if (cur is ActionPreferenceStopException &&
                    msg.IndexOf("ErrorActionPreference", StringComparison.OrdinalIgnoreCase) >= 0)
                    return true;
            }
            return false;
        }

        static bool IsEmptyResultRecord(ErrorRecord e)
        {
            if (e == null) return false;

            if (!string.IsNullOrEmpty(e.FullyQualifiedErrorId) &&
                e.FullyQualifiedErrorId.IndexOf("NotFound", StringComparison.OrdinalIgnoreCase) >= 0)
                return true;

            Exception ex = e.Exception;
            for (int i = 0; ex != null && i < 5; i++, ex = ex.InnerException)
            {
                if (ex.GetType().Name.IndexOf("CimJobException", StringComparison.OrdinalIgnoreCase) >= 0) return true;
                if (!string.IsNullOrEmpty(ex.Message) &&
                    ex.Message.IndexOf("NotFound", StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            return false;
        }

        /// <summary>
        /// 移除单个设备，按顺序尝试，任一级成功即返回 true。
        /// 1. Remove-PnpDevice      PnP 模块命令（存在时最规范）
        /// 2. pnputil /remove-device PnP 管理器命令行（实测有效）
        /// 3. 注册表删除            最后兜底，绕过 PnP 管理器
        /// </summary>
        public static bool Remove(string instanceId)
        {
            using (var ps = PowerShell.Create())
            {
                ps.AddScript(RemoveScript).AddArgument(instanceId);
                var res = ps.Invoke();

                if (ps.HadErrors)
                {
                    foreach (ErrorRecord e in ps.Streams.Error)
                        Logger.Write("    移除错误: " + Diagnostics.Describe(e));
                }

                return res.Count > 0 && res[0] != null && res[0].ToString() == "True";
            }
        }

        // 扫描通路一：PnpDevice 模块。输出 设备名 \t 实例ID \t 是否受保护(1/0)
        const string ScanByPnpDeviceScript = @"
$ErrorActionPreference = 'SilentlyContinue'

function Test-HasRealAffinity {
    param([string]$InstanceId)
    try {
        $afPath = ""HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters\Interrupt Management\Affinity Policy""
        if (Test-Path $afPath) {
            $a = Get-ItemProperty -Path $afPath -ErrorAction SilentlyContinue
            if ($null -ne $a.DevicePolicy -and $a.DevicePolicy -ge 3) { return $true }
            if ($a.AssignmentSetOverride) {
                foreach ($b in [byte[]]$a.AssignmentSetOverride) { if ($b -ne 0) { return $true } }
            }
        }
        return $false
    } catch { return $false }
}

$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($d in @(Get-PnpDevice -PresentOnly:$false -ErrorAction Stop | Where-Object { $_.Status -eq 'Unknown' })) {
    $id = ([string]$d.InstanceId).Trim()
    if ($seen.Contains($id)) { continue }
    [void]$seen.Add($id)
    $p = if (Test-HasRealAffinity -InstanceId $id) { '1' } else { '0' }
    $n = ([string]$d.FriendlyName).Trim() -replace ""[\t\r\n]"", ' '
    ""$n`t$id`t$p""
}
";

        // 扫描通路二：pnputil 枚举已断开连接的设备，不经过 WMI。
        // 设备名从注册表读取（pnputil 的说明文字受控制台代码页影响，可能乱码）
        const string ScanByPnputilScript = @"
$ErrorActionPreference = 'SilentlyContinue'

function Test-HasRealAffinity {
    param([string]$InstanceId)
    try {
        $afPath = ""HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters\Interrupt Management\Affinity Policy""
        if (Test-Path $afPath) {
            $a = Get-ItemProperty -Path $afPath -ErrorAction SilentlyContinue
            if ($null -ne $a.DevicePolicy -and $a.DevicePolicy -ge 3) { return $true }
            if ($a.AssignmentSetOverride) {
                foreach ($b in [byte[]]$a.AssignmentSetOverride) { if ($b -ne 0) { return $true } }
            }
        }
        return $false
    } catch { return $false }
}

function Get-FriendlyName {
    param([string]$InstanceId)
    try {
        $v = (Get-ItemProperty -Path ""HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId"" -Name FriendlyName -ErrorAction Stop).FriendlyName
        if ($v) { return ([string]$v).Trim() }
    } catch {}
    try {
        $v = (Get-ItemProperty -Path ""HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId"" -Name DeviceDesc -ErrorAction Stop).DeviceDesc
        if ($v) { return (([string]$v) -split ';')[-1].Trim() }
    } catch {}
    return $InstanceId
}

$raw = & ""$env:WINDIR\System32\pnputil.exe"" /enum-devices /disconnected 2>&1
if ($LASTEXITCODE -ne 0) { throw ""pnputil 退出码 $LASTEXITCODE"" }

$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($line in $raw) {
    $m = [regex]::Match([string]$line, '^\s*Instance ID:\s*(.+?)\s*$')
    if (-not $m.Success) { continue }
    $id = $m.Groups[1].Value.Trim()
    if (-not $id) { continue }
    if ($seen.Contains($id)) { continue }
    [void]$seen.Add($id)
    $p = if (Test-HasRealAffinity -InstanceId $id) { '1' } else { '0' }
    $n = (Get-FriendlyName -InstanceId $id) -replace ""[\t\r\n]"", ' '
    ""$n`t$id`t$p""
}
";

        // 移除：三级回退
        const string RemoveScript = @"
param([string]$id)
$removed = $false

# 第 1 级：PnpDevice 模块命令（部分系统未提供 Remove-PnpDevice）
try {
    if (Get-Command Remove-PnpDevice -ErrorAction SilentlyContinue) {
        Get-PnpDevice -InstanceId $id -ErrorAction Stop | Remove-PnpDevice -Confirm:$false -ErrorAction Stop
        $removed = $true
    }
} catch {}

# 第 2 级：pnputil（PnP 管理器命令行，实测对幽灵设备有效）
if (-not $removed) {
    try {
        $o = & ""$env:WINDIR\System32\pnputil.exe"" /remove-device ""$id"" 2>&1
        if ($LASTEXITCODE -eq 0) { $removed = $true }
    } catch {}
}

# 第 3 级：注册表直接删除（最后兜底，绕过 PnP 管理器）
if (-not $removed) {
    try {
        Remove-Item -Path ""HKLM:\SYSTEM\CurrentControlSet\Enum\$id"" -Recurse -Force -ErrorAction Stop
        $removed = $true
    } catch {}
}

return $removed
";
    }
}