using System;
using System.Diagnostics;
using System.Linq;
using System.Management.Automation;
using System.Text;

namespace WdcShell.Core
{
    /// <summary>
    /// 逐层探测设备查询链路，用于定位"扫描失效"究竟发生在哪一层。
    /// 每一层单独执行并计时，结果写入日志。
    /// </summary>
    public static class Diagnostics
    {
        /// <summary>依次执行各层探测，返回可读报告。</summary>
        public static string Run()
        {
            var sb = new StringBuilder();
            sb.AppendLine("=== 诊断开始 ===");
            sb.AppendLine("进程位数  : " + (Environment.Is64BitProcess ? "64 位" : "32 位"));
            sb.AppendLine();

            Check(sb, "1. WMI 服务状态", @"
$s = Get-Service Winmgmt -ErrorAction Stop
'Winmgmt 状态: ' + $s.Status
");

            Check(sb, "2. CIM 类定义查询", @"
$c = Get-CimClass -ClassName Win32_PnPEntity -ErrorAction Stop
'Win32_PnPEntity 类可访问, 属性数: ' + $c.CimClassProperties.Count
");

            Check(sb, "3. CIM 实例查询（前 3 个）", @"
$x = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Select-Object -First 3)
'Win32_PnPEntity 实例可取, 取样: ' + $x.Count
");

            Check(sb, "4. PnpDevice 模块加载", @"
$m = Get-Module -ListAvailable PnpDevice -ErrorAction Stop
'PnpDevice 模块: ' + $m.Count + ' 个'
");

            Check(sb, "5. Get-PnpDevice 全量", @"
$a = @(Get-PnpDevice -PresentOnly:$false -ErrorAction Stop)
'Get-PnpDevice 返回: ' + $a.Count + ' 个'
");

            Check(sb, "6. Get-PnpDevice 指定实例", @"
$a = @(Get-PnpDevice -ErrorAction Stop)
'仅在场设备: ' + $a.Count + ' 个'
");

            sb.AppendLine("=== 诊断结束 ===");
            return sb.ToString();
        }

        static void Check(StringBuilder sb, string title, string script)
        {
            sb.AppendLine("--- " + title + " ---");
            var sw = Stopwatch.StartNew();
            try
            {
                using (var ps = PowerShell.Create())
                {
                    ps.AddScript(script);
                    var res = ps.Invoke();
                    sw.Stop();

                    foreach (var r in res)
                        if (r != null) sb.AppendLine(r.ToString());

                    if (ps.HadErrors)
                    {
                        foreach (ErrorRecord e in ps.Streams.Error.Take(3))
                            sb.AppendLine("  PS 错误: " + Describe(e));
                    }
                    sb.AppendLine("  耗时 " + sw.ElapsedMilliseconds + " ms");
                }
            }
            catch (Exception ex)
            {
                sw.Stop();
                sb.AppendLine("  抛出异常（耗时 " + sw.ElapsedMilliseconds + " ms）:");
                AppendException(sb, "  ", ex);
            }
            sb.AppendLine();
        }

        /// <summary>把 PS 错误记录展开成可读文本（含内部异常）。</summary>
        public static string Describe(ErrorRecord e)
        {
            if (e == null) return "<null>";
            var sb = new StringBuilder();
            sb.Append(e.Exception == null ? "<无异常对象>" : e.Exception.GetType().FullName);

            string msg = e.Exception == null ? null : e.Exception.Message;
            sb.Append(" : ").Append(string.IsNullOrEmpty(msg) ? "<消息为空>" : msg);

            if (e.Exception != null && e.Exception.InnerException != null)
                sb.Append(" | 内部: ").Append(e.Exception.InnerException.GetType().Name)
                  .Append(" : ").Append(string.IsNullOrEmpty(e.Exception.InnerException.Message)
                                        ? "<消息为空>" : e.Exception.InnerException.Message);

            if (e.CategoryInfo != null && e.CategoryInfo.Category != ErrorCategory.NotSpecified)
                sb.Append(" | 类别: ").Append(e.CategoryInfo.Category.ToString());

            return sb.ToString();
        }

        /// <summary>把异常及其内部异常链写入 StringBuilder。</summary>
        public static void AppendException(StringBuilder sb, string indent, Exception ex)
        {
            int level = 0;
            for (Exception e = ex; e != null && level < 5; e = e.InnerException, level++)
            {
                string tag = level == 0 ? "" : "内部" + level + " ";
                sb.AppendLine(indent + tag + e.GetType().FullName);
                sb.AppendLine(indent + "  消息: " + (string.IsNullOrEmpty(e.Message) ? "<空>" : e.Message));
                if (!string.IsNullOrEmpty(e.Source)) sb.AppendLine(indent + "  来源: " + e.Source);

                var agg = e as AggregateException;
                if (agg != null)
                    foreach (Exception inner in agg.InnerExceptions)
                        sb.AppendLine(indent + "  聚合: " + inner.GetType().FullName + " : " + inner.Message);

                if (!string.IsNullOrEmpty(e.StackTrace))
                    foreach (string line in e.StackTrace.Split('\n'))
                        if (line.Trim().Length > 0) sb.AppendLine(indent + "  " + line.Trim());
            }
        }
    }
}