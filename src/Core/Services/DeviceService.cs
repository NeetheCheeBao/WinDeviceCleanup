using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using WdcShell.Core;

namespace WdcShell.Services
{
    /// <summary>一次扫描的结果统计。</summary>
    public class ScanResult
    {
        public List<DeviceItem> Devices;
        public int GhostCount;
        public int ProtectedCount;
        public long ElapsedMs;
    }

    /// <summary>移除进度。</summary>
    public class RemoveProgress
    {
        public int Done;
        public int Total;
        public int Ok;
        public int Failed;
    }

    /// <summary>
    /// 业务流程编排：在后台线程调用 PowerShell 后端，通过回调把结果送回 UI 线程。
    /// 界面层只负责把回调收到的数据画出来。
    /// </summary>
    public static class DeviceService
    {
        /// <summary>扫描设备。onDone 在 UI 线程被调用，参数为 null 表示失败。</summary>
        public static void ScanAsync(Action<ScanResult> onDone, Action<string> onError)
        {
            Task.Run(delegate
            {
                Logger.Write("  [后台] 扫描任务开始");
                var sw = Stopwatch.StartNew();
                List<DeviceItem> found = null;
                string error = null;

                try { found = PowerShellBackend.Scan(); }
                catch (Exception ex) { error = ex.Message; Logger.Error("扫描", ex); }

                sw.Stop();
                if (error == null)
                    Logger.Write("  [后台] 扫描任务返回: " + found.Count + " 个条目，耗时 " + sw.ElapsedMilliseconds + " ms");
                else
                    Logger.Write("  [后台] 扫描任务异常返回");

                AppState.Window.Dispatcher.Invoke(new Action(delegate
                {
                    if (error != null)
                    {
                        onError(error);
                        return;
                    }

                    Logger.Write("  [界面] 扫描结果已应用");
                    var result = new ScanResult
                    {
                        Devices = found,
                        GhostCount = found.Count(delegate (DeviceItem x) { return !x.IsProtected; }),
                        ElapsedMs = sw.ElapsedMilliseconds
                    };
                    result.ProtectedCount = found.Count - result.GhostCount;

                    onDone(result);
                }));
            });
        }

        /// <summary>逐个移除设备。onProgress / onDone 均在 UI 线程被调用。</summary>
        public static void RemoveAsync(IList<DeviceItem> selected,
                                       Action<RemoveProgress> onProgress,
                                       Action<RemoveProgress> onDone)
        {
            var ids = selected.Select(delegate (DeviceItem x) { return x.InstanceId; }).ToArray();
            int total = ids.Length;

            Task.Run(delegate
            {
                Logger.Write("  [后台] 移除任务开始");
                int ok = 0, failed = 0;

                Logger.Write("开始移除  : 共 " + total + " 个设备");
                int index = 0;
                foreach (string id in ids)
                {
                    index++;
                    bool done = false;
                    try { done = PowerShellBackend.Remove(id); }
                    catch (Exception ex) { Logger.Error("移除 " + id, ex); }

                    Logger.Write("  [" + index + "/" + total + "] " + (done ? "成功" : "失败") + "  " + id);

                    if (done) ok++; else failed++;

                    int doneCount = ok + failed, okNow = ok, failNow = failed;
                    AppState.Window.Dispatcher.Invoke(new Action(delegate
                    {
                        onProgress(new RemoveProgress
                        {
                            Done = doneCount,
                            Total = total,
                            Ok = okNow,
                            Failed = failNow
                        });
                    }));
                }

                int finalOk = ok, finalFailed = failed;
                Logger.Write("  [后台] 移除任务结束: 成功 " + finalOk + " 个，失败 " + finalFailed + " 个");
                AppState.Window.Dispatcher.Invoke(new Action(delegate
                {
                    Logger.Write("  [界面] 移除结果已应用，即将触发复扫");
                    onDone(new RemoveProgress
                    {
                        Done = total,
                        Total = total,
                        Ok = finalOk,
                        Failed = finalFailed
                    });
                }));
            });
        }
    }
}