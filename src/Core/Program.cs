using System;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Markup;
using WdcShell.Core;

namespace WdcShell
{
    /// <summary>
    /// 程序入口。对应 C++ 项目的 main.cpp。
    /// </summary>
    public static class Program
    {
        [STAThread]   // WPF 要求 UI 线程为单线程单元（STA），等价于 C++ 的 CoInitializeEx(COINIT_APARTMENTTHREADED)
        public static void Main()
        {
            Logger.Start();
            try
            {
                var app = new Application();
                app.ShutdownMode = ShutdownMode.OnExplicitShutdown;

                string xaml = LoadXaml();
                Logger.Write("XAML 来源  : " + XamlSource);
                if (xaml == null)
                {
                    MessageBox.Show(
                        "未找到界面定义 MainWindow.xaml。\n\n" +
                        "· 发布版：应由 build.bat 将 MainWindow.xaml 内嵌为资源\n" +
                        "· 开发期：请确认 MainWindow.xaml 与程序集同目录，或设置 WDC_XAML 环境变量指向它",
                        "WinDeviceCleanup", MessageBoxButton.OK, MessageBoxImage.Error);
                    return;
                }

                AppState.Window = (Window)XamlReader.Load(new System.Xml.XmlTextReader(new StringReader(xaml)));

                MainWindow.Bind();
                MainWindow.WireEvents();

                AppState.Window.ShowDialog();
            }
            catch (Exception ex)
            {
                Logger.Error("启动过程", ex);
                ReportStartupFailure(ex);
            }
            finally
            {
                Logger.Stop();
            }
        }

        /// <summary>XAML 的实际来源，仅用于日志。</summary>
        static string XamlSource = "未知";

        /// <summary>取 XAML：内嵌资源 → WDC_XAML 环境变量 → 程序集同目录</summary>
        static string LoadXaml()
        {
            var asm = typeof(Program).Assembly;

            using (var s = asm.GetManifestResourceStream("MainWindow.xaml"))
            {
                if (s != null)
                {
                    XamlSource = "内嵌资源";
                    using (var r = new StreamReader(s, Encoding.UTF8))
                        return r.ReadToEnd();
                }
            }

            string env = Environment.GetEnvironmentVariable("WDC_XAML");
            if (!string.IsNullOrEmpty(env) && File.Exists(env))
            {
                XamlSource = "环境变量 WDC_XAML -> " + env;
                return File.ReadAllText(env, Encoding.UTF8);
            }

            string dir = null;
            try { dir = System.IO.Path.GetDirectoryName(asm.Location); }
            catch { }
            if (!string.IsNullOrEmpty(dir))
            {
                string p = System.IO.Path.Combine(dir, "MainWindow.xaml");
                if (File.Exists(p))
                {
                    XamlSource = "程序集同目录 -> " + p;
                    return File.ReadAllText(p, Encoding.UTF8);
                }
            }
            return null;
        }

        static void ReportStartupFailure(Exception ex)
        {
            var sb = new StringBuilder();
            sb.AppendLine("TYPE: " + ex.GetType().FullName);
            sb.AppendLine("MSG: " + ex.Message);
            sb.AppendLine("STACK: " + ex.StackTrace);

            if (ex.InnerException != null)
            {
                sb.AppendLine("INNER: " + ex.InnerException.GetType().FullName + " : " + ex.InnerException.Message);
                sb.AppendLine("INNER-STACK: " + ex.InnerException.StackTrace);
            }

            var xpe = ex as XamlParseException;
            if (xpe != null) sb.AppendLine("XAML LINE: " + xpe.LineNumber + " POS: " + xpe.LinePosition);

            try
            {
                string logPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "wdc_error.log");
                File.WriteAllText(logPath, sb.ToString(), Encoding.UTF8);
                MessageBox.Show(sb.ToString(),
                    "WinDeviceCleanup - 启动失败 (日志: " + logPath + ")",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
            catch { }
        }
    }
}