using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace WdcShell.Core
{
    /// <summary>
    /// 运行日志。每次启动新建一个文件，写在 exe 同目录的 log\ 下。
    /// 用于在无法直接观察的机器（例如虚拟机）上排查问题。
    /// </summary>
    public static class Logger
    {
        static StreamWriter _writer;
        static string _path;

        /// <summary>已打开的日志文件路径，未打开时为 null。</summary>
        public static string Path { get { return _path; } }

        /// <summary>日志目录：exe 同目录下的 WDC_log\。</summary>
        public static string Directory
        {
            get { return System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "WDC_log"); }
        }

        /// <summary>开始记录。调用失败时静默降级，不影响程序运行。</summary>
        public static void Start()
        {
            try
            {
                System.IO.Directory.CreateDirectory(Directory);
                _path = System.IO.Path.Combine(Directory,
                    "wdc_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".log");
                _writer = new StreamWriter(_path, false, new UTF8Encoding(false));
                _writer.AutoFlush = true;

                Write("=== WinDeviceCleanup 启动 ===");
                Write("时间      : " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                Write("程序版本  : 2.0");
                Write("可执行文件: " + Process.GetCurrentProcess().MainModule.FileName);
                Write("操作系统  : " + Environment.OSVersion.VersionString);
                Write("64 位系统 : " + Environment.Is64BitOperatingSystem);
                Write("权限状态  : " + MainWindow.GetPermissionStatus());
            }
            catch
            {
                _writer = null;
                _path = null;
            }
        }

        /// <summary>停止记录。</summary>
        public static void Stop()
        {
            try
            {
                if (_writer != null)
                {
                    Write("=== 程序退出 ===");
                    _writer.Flush();
                    _writer.Dispose();
                }
            }
            catch { }
            finally { _writer = null; }
        }

        public static void Write(string message)
        {
            if (_writer == null) return;
            try { _writer.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss.fff") + "] " + message); }
            catch { }
        }

        public static void Error(string context, Exception ex)
        {
            if (ex == null) { Write("错误 " + context + " : <null>"); return; }

            int level = 0;
            for (Exception e = ex; e != null && level < 5; e = e.InnerException, level++)
            {
                string prefix = level == 0 ? "错误 " : "   内部 " + level + " ";
                Write(prefix + context + " : " + e.GetType().FullName);
                Write(prefix + "  消息: " + (string.IsNullOrEmpty(e.Message) ? "<空>" : e.Message));

                if (!string.IsNullOrEmpty(e.Source)) Write(prefix + "  来源: " + e.Source);

                // AggregateException 等可能携带多个内部异常
                var agg = e as AggregateException;
                if (agg != null)
                    foreach (Exception inner in agg.InnerExceptions)
                        Write(prefix + "  聚合: " + inner.GetType().FullName + " : " + inner.Message);

                if (!string.IsNullOrEmpty(e.StackTrace))
                    foreach (string line in e.StackTrace.Split('\n'))
                        if (line.Trim().Length > 0) Write(prefix + "  " + line.Trim());
            }
        }
    }
}