using System;
using System.Linq;
using System.Management.Automation;
using System.Text;

namespace WdcShell.Core
{
    /// <summary>
    /// 无害探测：只做查询，不修改任何系统状态。
    /// 用于在"扫描失效"后采集现场，判断故障发生在哪一层。
    /// </summary>
    public static class Probe
    {
        const string Script = @"
$out = New-Object System.Collections.Generic.List[string]

# A. PowerShell 与 CLR
$out.Add('A PSVersion    : ' + $PSVersionTable.PSVersion.ToString() + ' / ' + $PSVersionTable.PSEdition)

# B. PnpDevice 模块
$m = @(Get-Module -ListAvailable PnpDevice -ErrorAction SilentlyContinue)
$out.Add('B PnpDevice模块: ' + $m.Count + ' 个')

# C. CimCmdlets 模块
$c = @(Get-Module -ListAvailable CimCmdlets -ErrorAction SilentlyContinue)
$out.Add('C CimCmdlets   : ' + $c.Count + ' 个')

# D. 直接 CIM 查询设备实体（绕开 Get-PnpDevice）
try {
    $n = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop).Count
    $out.Add('D 直接CIM查询  : 成功, ' + $n + ' 个实体')
} catch {
    $out.Add('D 直接CIM查询  : 失败 -> ' + $_.Exception.GetType().FullName + ' : ' + $_.Exception.Message)
}

# E. Get-PnpDevice 最简调用
try {
    $x = @(Get-PnpDevice -ErrorAction Stop)
    $out.Add('E Get-PnpDevice(在场): 成功, ' + $x.Count + ' 个')
} catch {
    $out.Add('E Get-PnpDevice(在场): 失败 -> ' + $_.Exception.GetType().FullName + ' : ' + $_.Exception.Message)
}

# F. Get-PnpDevice 全量调用
try {
    $y = @(Get-PnpDevice -PresentOnly:$false -ErrorAction Stop)
    $out.Add('F Get-PnpDevice(全量): 成功, ' + $y.Count + ' 个')
} catch {
    $out.Add('F Get-PnpDevice(全量): 失败 -> ' + $_.Exception.GetType().FullName + ' : ' + $_.Exception.Message)
}

# G. WMI 服务
try {
    $s = Get-Service Winmgmt -ErrorAction Stop
    $out.Add('G Winmgmt服务  : ' + $s.Status)
} catch {
    $out.Add('G Winmgmt服务  : 查询失败 -> ' + $_.Exception.Message)
}

$out
";

        /// <summary>执行探测，返回报告文本。</summary>
        public static string Run()
        {
            var sb = new StringBuilder();
            sb.AppendLine("=== 设备查询探测（只读） ===");

            try
            {
                using (var ps = PowerShell.Create())
                {
                    ps.AddScript(Script);
                    var res = ps.Invoke();

                    foreach (var r in res)
                        if (r != null) sb.AppendLine(r.ToString());

                    sb.AppendLine();
                    sb.AppendLine("HadErrors      : " + ps.HadErrors);
                    sb.AppendLine("Error 条数     : " + ps.Streams.Error.Count);

                    int i = 0;
                    foreach (ErrorRecord e in ps.Streams.Error)
                    {
                        i++;
                        sb.AppendLine("  [错误 " + i + "] " + DescribeRecord(e));
                    }

                    sb.AppendLine("Warning 条数   : " + ps.Streams.Warning.Count);
                    sb.AppendLine("Verbose 条数   : " + ps.Streams.Verbose.Count);
                }
            }
            catch (Exception ex)
            {
                sb.AppendLine("探测本身抛出异常:");
                Diagnostics.AppendException(sb, "  ", ex);
            }

            sb.AppendLine("=== 探测结束 ===");
            return sb.ToString();
        }

        /// <summary>把 ErrorRecord 展开，连 Exception 为 null 的情况也说明清楚。</summary>
        public static string DescribeRecord(ErrorRecord e)
        {
            if (e == null) return "<ErrorRecord 为 null>";

            var sb = new StringBuilder();
            sb.Append("FullyQualifiedErrorId=").Append(e.FullyQualifiedErrorId ?? "<null>");
            sb.Append(" | Exception=");

            if (e.Exception == null)
            {
                sb.Append("<null>");
            }
            else
            {
                sb.Append(e.Exception.GetType().FullName);
                sb.Append(" : ").Append(string.IsNullOrEmpty(e.Exception.Message) ? "<消息为空>" : e.Exception.Message);

                Exception inner = e.Exception.InnerException;
                int level = 0;
                while (inner != null && level < 4)
                {
                    level++;
                    sb.Append(" | 内部").Append(level).Append('=')
                      .Append(inner.GetType().FullName).Append(" : ")
                      .Append(string.IsNullOrEmpty(inner.Message) ? "<消息为空>" : inner.Message);
                    inner = inner.InnerException;
                }
            }

            if (e.ErrorDetails != null) sb.Append(" | Details=").Append(e.ErrorDetails.ToString());
            return sb.ToString();
        }
    }
}